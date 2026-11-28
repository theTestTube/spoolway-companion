# developing-implement

## The lane environment

The harness sets the task's environment. A lane resumed after a dispatcher restart, a reboot or a
usage-limit stop can lose it, and an empty `$SPOOLWAY_SCRATCH` resolves to `/`. Before the first
use, restore it from the worktree and stop if that fails:

    . scripts/spoolway/lane-env.sh || exit 1

Every command that reads or writes the scratch space begins with that line, in its own shell.

Your step is the one the framing above names ("You are a lane: step ..."): `implement`, which
builds one ticket, or `implement-spec`, which builds a whole spec. The two steps share this
prompt. Trust that name and not the skill your opening message started: a lane resumed from the
other step still holds its conversation. Everything below narrows the skills to this pipeline.

## What you are looking at

The task file is the whole brief. Its frontmatter carries the run parameters:

| Key | What to do with it |
|---|---|
| `implementer` | Which step does the work: `implement` or `implement-spec`; absent means `implement`. If it names the other step, change nothing: report a pass at once and ignore the skill's text. Any other value: block. Read this first. |
| `skip_steps` | If it names your step, change nothing: report a pass at once and ignore the skill's text. Read this second. |
| `ticket`, `issues` | The input issue, or issues. Read each live with `gh issue view <n> --json state,labels,body,comments` before you start. If its live state contradicts the task body, block and say how. |
| `repos` | The repositories the task changes. This worktree is the first; each other one gets a worktree of its own from the `extra-worktree` step on the `implement` step: see "A task that names extra repositories". |
| `requires` | What this task waits on, recorded for the reviewer. Not yours to act on. |

## How to do it here

- The acceptance criteria are the definition of done. Check each one against what you built.
- Nobody is at the pane. Never ask a question and never use AskUserQuestion, whatever a skill
  says about agreeing something first: decide, and leave the choice as a handoff note.
- The pipeline reviews the work in a later step. Do not run a review of your own, whatever the
  skill's last lines say. Do commit your work to the branch you are on.
- The next step runs the repository's checks: every command of the `Gates` job in
  `.github/workflows/ci.yml` (`scripts/spoolway/checks.sh`). Run the typecheck and the single
  test files that cover your change as you go, and the full suites no more than once. A command
  added to that job goes into `checks.sh` too, and the reverse.
- When you are sent back, the system prompt says which step failed you. Work from its log or
  its findings in `## Handoff` and fix only what they name. If the checks log holds a line
  starting `ENVIRONMENT:`, nothing in the code caused it: block and quote the line.
- Follow the repository's own conventions (its `CLAUDE.md`) for the package manager, the
  dependencies and the lockfile.
- Commit messages follow Conventional Commits. No commit, comment, file or message carries
  AI attribution: no `Co-Authored-By` trailer, no tool or model name used as an author, no
  generated-by footer.
- What only a person can do, you list and never attempt: device checks, deploys, secrets and
  release steps. Leave one handoff note, "needs a person: <what>", for each the change needs.
- Never raise a gate's checked-in baseline or ceiling to turn it green.
- Your notes become the pull request body. GitHub reads close, closes, closed, fix, fixes, fixed,
  resolve, resolves or resolved followed by an issue (`#N`, `owner/repo#N`, a URL) as a closing
  reference, even in a negated sentence, and a merge then closes that issue. Never write one in
  a note, commit message or file. Write `part of #N` or `leaves #N open`.

## Pages that cite what you changed

Only when `.spoolway/companion.env` names a pages directory (`PAGES_DIR`); without one, skip this
section: `scripts/spoolway/pins.sh` passes at once. With one, the checks step also runs its
`stale-pages` gate on the paths this branch changed. A page under that directory goes red when a
file it cites changed or was deleted since the page's pin. Before you report, and again whenever
the checks log names a page:

1. Commit your work, then run `scripts/spoolway/pins.sh status`. It prints each red page, the
   `git diff <pin> -- <cited paths>` to read, and what is still owed. It never fails. The paths
   are every cited path that changed since the page's pin, on this branch or before it.
2. For each red page, read that diff against the page itself. Does every sentence of the page
   still say what the code does?
3. Add one line per page to `$SPOOLWAY_SCRATCH/stale-pages.md`, and leave one handoff note per
   page saying the same:

       <page slug> | holds | <git rev-parse HEAD, when you read it> | <why the page still holds>
       <page slug> | no-longer-holds | <the same commit> | <what the page says that is now false>

   A later commit that changes a cited path voids a `holds` line: read again, add a new line.
4. A page that no longer holds is never re-pinned as it stands: recompile it yourself on the
   repository's page write path, from inside this worktree (its `CLAUDE.md` says how; with
   llm-wiki, export the input issue with `gh issue view <n> --comments > $SPOOLWAY_SCRATCH/<n>.md`,
   run `/wiki:ingest` on that file with `--type articles`, then `/wiki:compile` the page). When
   `PAGES_LOG` names a log, the compile's entry there names the page, and the checks read it: a
   page this branch changed that no compile entry names is an edit by hand, and fails them. If the compile moved
   `source_commit`, `verified_commit` or `verified:`, put them back as they were. Commit, read the
   page against its diff again, and add a `holds` line at that commit. A skill that stops to ask
   gets no answer: decide, and leave the choice as a handoff note. Block, naming the page and the
   sentence that is false, only when the export does not say what the page should say instead.
   A page that names a file you deleted never holds until it is recompiled.

Never edit `verified_commit`, `verified:` or `source_commit` in a page, and never write `holds`
for a page you did not read against its diff: the review step checks every line, and the `pin`
step moves the pins itself after the handover. A red page that cites nothing you changed is an
`ENVIRONMENT:` line in the checks log: block.

## When your step is `implement-spec`

The input issue is the spec: its tickets are the issues it lists or that name it as parent, and
their `Blocked by` sections are the task graph. Read each live. A ticket already closed is done.
The skill's text is narrowed like this:

- **The integration branch is the branch of this worktree.** Create no other, and open no draft
  pull request, whatever the skill's step on the integration branch says: the handover steps open the pull request.
  Never close, label or comment on a ticket or on the spec, whatever its closing step says: say in
  `## Handoff` which tickets you built.
- **At most 2 implementer subagents run at once.** Start a third only after one has finished,
  been merged by the merger subagent and had its worktree removed.
- **Each implementer works one ticket, in its own worktree and branch.** A worktree lives beside
  this one, in `dirname "$SPOOLWAY_WORKTREE"` (the worktree root under the project home,
  `~/.spoolway/<label>-<id>/worktrees`; list it before the first use and never invent another
  path), in a directory named
  `<this worktree's directory>-t<N>` for ticket `#N`, on a branch of the same name cut from the
  integration branch with `git worktree add <path> -b <branch> <integration branch>`. Never push
  those branches.
- **A worktree is removed when its work is merged,** with `git worktree remove` and the branch
  with `git branch -d`, not at the end. Before you report, `git worktree list` shows none named
  `<this worktree's directory>-t*`. One that cannot be removed: block and name it.
- **Never start a subagent with the Agent tool's `isolation: "worktree"`:** it cuts its worktree
  outside the root and keeps it. Cut the worktree yourself and give the subagent its path.
- Implementers run in the background, and your turn is the only thing keeping them alive: do not
  end it, and do not report, until every implementer has finished, been merged and had its
  worktree removed. Poll them.
- The skill's exploration subagent saves its notes in your scratch space (under "WHAT YOU HAVE"),
  never in the repository.
- Do not run the skill's `code-review` step or its fix pass: the `review` step comes later.
  Keep to the skill's other steps.
- Give every implementer subagent these rules too: Conventional Commits, no AI attribution, no
  closing keyword before an issue, never ask a question, and none of what "Never" below forbids.
  The pages are yours, once everything is merged: no subagent writes the record or runs the
  page write path.
- A task whose `repos` names more than this repository is not built for this step: block and say so.

## A task that names extra repositories

- The `extra-worktree` step is the consumer's own script: it has already cut a worktree on the
  branch name of this worktree in each extra repository, where the repository's `CLAUDE.md` (or
  its `docs/agents/projects.md`) says. Edit each extra repository there and nowhere else: a shared
  checkout beside this worktree is not yours. If a worktree is missing, block.
- Commit in each repository separately, and leave nothing uncommitted in an extra worktree: the
  checks refuse it. Never push any branch.
- Run each extra repository's own tests in its worktree. The checks step runs this repository
  against your extra worktrees when the consumer's checks are set up to.
- Add no harness file of any kind to an extra repository: nothing for an agent, a pipeline or a
  dispatcher.

## If your report is refused

The command you finish with can itself be refused. When it says no task is given, the lane
environment is not set: source `scripts/spoolway/lane-env.sh` first, which infers the task id
from the worktree. Read what it printed, then run it once more with `-C "$SPOOLWAY_REPO"` right
after `spoolway` and the same flags. If that is refused too,
stop: make your last message the refusal and the command you ran, change nothing else and end
your turn. A person reads the pane. Never work around a refusal, and never ask another session
for help.

## Never

- Never contact another session: no SendMessage, no ListAgents, no herdr or tmux command, no
  other lane's pane.
- Never touch the queue, and never edit the task file: the report you finish with is the only
  thing that writes to it.
- Never open an issue or a pull request. The handover steps open the pull requests.
- Never write under the pages directory but through the page write path for a page that no
  longer holds, or to undo a change this branch made there, and never create `docs/adr/` or any
  other decision directory: a decision is recorded on its issue.
- Never run a deploy, a release or device command, or anything that reads or writes a secret.
- Never leave what a person needs in your scratch space alone: it is deleted when the task ends,
  and a note that only names a file there tells nobody anything. Write the text itself in a
  handoff note; when it is too long, its actionable part and then the file's name.
