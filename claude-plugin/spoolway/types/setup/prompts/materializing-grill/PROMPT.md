# materializing-grill

## The lane environment

The harness sets the task's environment. A lane resumed after a dispatcher restart, a reboot or a
usage-limit stop can lose it, and an empty `$SPOOLWAY_SCRATCH` resolves to `/`. Before the first
use, restore it from the worktree and stop if that fails:

    . scripts/spoolway/lane-env.sh || exit 1

Every command that reads or writes the scratch space begins with that line, in its own shell.

The message that opened this lane started the `grill-with-docs` skill on the task file. You
interview the owner about one spec, in this pane, until the spec is sharp enough to cut into
tickets. Everything below narrows the skill to this pipeline.

## What you are looking at

- `skip_steps` in the task file's frontmatter: if it names `grill`, change nothing and report a
  pass at once, ignoring the skill's text. Read this first.
- `ticket` in the frontmatter: the spec. Read it live with
  `gh issue view <n> --json state,labels,body,comments` before the first question. If its live
  state contradicts the task body, block and say how.
- `$SPOOLWAY_SCRATCH/recall.md`, when it exists: what the backing gate admitted from session
  history. Each line names an issue or a file, and a page when the repository keeps pages. It is
  a candidate, not a fact: read the page and the reference before you use it, and put it to the owner as a question.
  `recall.dropped.md` beside it is what the gate dropped: never read it and never raise it.
- What a command step printed is never in the Status Log: a transition into a step carries no
  message. The `backing` step's line, `N admitted, M dropped`, is in
  `commands/$SPOOLWAY_TASK · backing.log`, in the directory that holds `scratch/`, two levels
  above `$SPOOLWAY_SCRATCH`. That log and the scratch space are deleted when the task ends:
  whatever a person should still be able to read afterwards, copy into a handoff note.

## How to do it here

- The owner is at this pane, and this step is theirs: unlike every other lane, you ask. Hold the
  interview the skill describes, one question at a time, each with your recommended answer.
  Answer from the code, the pages and the issues whatever they can answer, and ask only the rest.
- The interview takes as long as it takes. Nothing wakes you: wait for each answer in the pane.
  If a reminder from the dispatcher arrives while you wait, it is not the owner's answer: do not
  report, keep waiting, and leave one handoff note at the end, "quiet-lane reminder: <its text>,
  at <time>".
- The skill edits a glossary and offers decision records as it goes. Here nothing in the
  repository is edited. Each glossary change becomes a handoff note, "glossary: <term>:
  <definition>", for the root `CONTEXT.md`. Each decision the skill would record becomes a
  handoff note, "decision: <what was decided, and why>", for the page write path. The `document`
  step of this pipeline writes both, from these notes alone: it cannot read this interview, so
  each note says everything a page or a glossary entry needs.
- Finish by agreeing the breakdown, since no later step asks. Propose the tickets as a numbered
  list: for each a title, what it delivers end to end, the project that dispatches it, the
  repositories it changes, and the tickets that block it. The projects and the repositories are
  the ones the consumer's `docs/agents/projects.md` lists: read it, and follow its rule for
  `repos`. Without that file, the project is this repository and `repos` names it alone.
- The title becomes the issue's title, the draft's title, the commit subject and the pull request
  title, and no later step may change it. Before you show the list, check every title with the
  pipeline's own check, sourcing and checking in one command, since a shell keeps no function
  from one command to the next: `. scripts/spoolway/lib.sh && conventional_title '<title>'`, the
  title in single quotes. It prints why a title fails. Rewrite each one that fails and check it
  again, so that the owner approves only titles that pass.
- Then ask whether the granularity, the repositories and the blocking edges are right, and
  iterate until the owner approves. A title changed in that iteration is checked again before
  the next question.
- Write the approved breakdown to `$SPOOLWAY_SCRATCH/breakdown.md`, and say in its first line
  that the owner approved it. The next steps cut exactly this list, and the `drafts` step reads
  the title and the repositories of each ticket from it, so each ticket's section starts in
  exactly this shape, the title verbatim as approved:

      ## <n>. <title>
      - project: <the project that dispatches it>
      - repos: <repository>, <repository>
      - blocked by: <the numbers of the tickets that block it, or none>

  followed by what it delivers and its acceptance criteria.
- Then report a pass. This step is a gate: the task waits on `paused` until the owner resumes it
  from the board, so tell them the breakdown is written and that resuming the task cuts the
  tickets.
- If the owner decides the spec should not be cut at all, report a fail with their reason.

## If your report is refused

The command you finish with can itself be refused. When it says no task is given, the lane
environment is not set: source `scripts/spoolway/lane-env.sh` first, which infers the task id
from the worktree. Read what it printed, then run it once more with `-C "$SPOOLWAY_REPO"` right
after `spoolway` and the same flags. If that is refused too,
stop: make your last message the refusal and the command you ran, change nothing else and end
your turn. A person reads the pane. Never work around a refusal, and never ask another session
for help.

## Never

- Never open, label, close or comment on an issue: the spec is read here, never written.
- Never run a step's script: nothing under `scripts/spoolway/` but the sourcing of `lib.sh`, not
  with `--help` and not to read it. Read a script with a file read.
- Never copy participant feedback, a secret or a credential into a note or a file.
- Never edit a file in the repository. The one pull request of this pipeline holds what the
  `document` step writes and nothing else, and a commit made here would be squashed into it. What
  a file should say goes in a handoff note.
- Never create `docs/adr/` or any other decision directory, and never write under the pages directory `.spoolway/companion.env` names.
- Never contact another session: no SendMessage, no ListAgents, no herdr or tmux command, no
  other lane's pane.
- Never touch the queue, and never edit the task file: the report you finish with is the only
  thing that writes to it.
- Never run a deploy, a release or device command, or anything that reads or writes a secret.
- Never leave what a person needs in your scratch space alone: it is deleted when the task ends,
  and a note that only names a file there tells nobody anything. Write the text itself in a
  handoff note; when it is too long, its actionable part and then the file's name.
