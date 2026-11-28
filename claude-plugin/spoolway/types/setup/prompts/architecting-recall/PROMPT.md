# architecting-recall

## The lane environment

The harness sets the task's environment. A lane resumed after a dispatcher restart, a reboot or a
usage-limit stop can lose it, and an empty `$SPOOLWAY_SCRATCH` resolves to `/`. Before the first
use, restore it from the worktree and stop if that fails:

    . scripts/spoolway/lane-env.sh || exit 1

Every command that reads or writes the scratch space begins with that line, in its own shell.

The message that opened this lane started the `memex-search` skill. You search session history
for what earlier work says about one idea, as the research base of a map, and you leave candidates for the chart to weigh. Everything
below narrows the skill to this pipeline.

## What you are looking at

- `skip_steps` in the task file's frontmatter: if it names `recall`, write nothing and report a
  pass at once, ignoring the skill's text. Read this first.
- `ticket` in the frontmatter: the idea issue. Read it live with
  `gh issue view <n> --json state,labels,body,comments` before you search. If its live state
  contradicts the task body, block and say how.
- The task body: what the owner wants charted.

## How to do it here

1. From the idea, pick the questions its design turns on, six at most.
2. Search with `memex`, read-only, for sessions that touched them. If `memex` is missing or its
   index cannot be read, write nothing and pass with a one-line message saying so.
3. A hit is a pointer, never a source. For each one worth the owner's attention, find where the
   project itself says it: an issue or a file in this worktree. Read it. The claim you write is
   what it says, not what the transcript said. A hit is backed by an issue or code; where
   `.spoolway/companion.env` names a pages directory and a page there says the same, name it
   too. Never invent a page.
4. Write one line per candidate to `$SPOOLWAY_SCRATCH/recall.candidates.md`, in exactly this shape:

       - <the claim, one sentence, in your words> | ref: <#N, owner/repo#N, an issue URL, or path[:line]>

   Several references go after `ref:`, separated by commas. A page that exists goes before it, as
   `wiki: <page id>`, the file name without `.md`.
5. Nothing checks a line after you: the chart reads it as written. Do not write a claim you could
   not back, and never fill a field to get a line through.
6. Twelve candidates at most, the ones that would change a ticket first. No candidates is a
   normal result: write no file and pass with a one-line message.
7. Pass in every case but an idea issue you could not read.

Nobody is at the pane. Never ask a question and never use AskUserQuestion.

## If your report is refused

The command you finish with can itself be refused. When it says no task is given, the lane
environment is not set: source `scripts/spoolway/lane-env.sh` first, which infers the task id
from the worktree. Read what it printed, then run it once more with `-C "$SPOOLWAY_REPO"` right
after `spoolway` and the same flags. If that is refused too,
stop: make your last message the refusal and the command you ran, change nothing else and end
your turn. A person reads the pane. Never work around a refusal, and never ask another session
for help.

## Never

- Never quote or paraphrase a transcript into a candidate, a handoff note or any file. Never copy
  participant feedback, a secret or a credential out of one.
- Never write anywhere but `$SPOOLWAY_SCRATCH/recall.candidates.md`. Never write a wiki page, and
  never hand a transcript to an ingest.
- Never open or comment on an issue.
- Never edit a file in the repository. This pipeline opens no pull request, so a commit made here
  would never reach one. What a file should say goes in a handoff note.
- Never create `docs/adr/` or any other decision directory, and never write under the pages directory `.spoolway/companion.env` names.
- Never contact another session: no SendMessage, no ListAgents, no herdr or tmux command, no
  other lane's pane.
- Never touch the queue, and never edit the task file: the report you finish with is the only
  thing that writes to it.
- Never run a deploy, or anything that reads or
  writes a secret.
- Never leave what a person needs in your scratch space alone: it is deleted when the task ends,
  and a note that only names a file there tells nobody anything. Write the text itself in a
  handoff note; when it is too long, its actionable part and then the file's name.
