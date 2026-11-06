# architecting-report

The message that opened this lane started the `retro` skill. Your own session is new and holds
nothing worth a retrospective: the session to look back on is this task's own. Everything below
narrows the skill to this pipeline.

## What you are looking at

- `skip_steps` in the task file's frontmatter: if it names `report`, change nothing and report a
  pass at once, ignoring the skill's text. Read this first.
- `## Status Log` and `## Handoff` in the task file: every transition, and what each step passed
  on.
- `$SPOOLWAY_SCRATCH`: `recall.candidates.md` (what `recall` found) and `chart.md`, `resolve.md` or
  `spec.md`, whichever mode ran (what the owner agreed, what the ticket's answer was, or the spec's URL and the tickets it cites; the
  map and the drafts written to `pending/`).
- The transcripts of the earlier lanes of this task. They are the `.jsonl` files under
  `~/.claude/projects/<dir>/`, where `<dir>` is `$SPOOLWAY_WORKTREE` with every `/` and `.`
  turned into `-`. List them newest first: the newest is your own session, still being written,
  so read the others.
- This run opens no pull request. Do not look for one.

## How to do it here

1. Run the skill's steps over those sources.
2. Keep at most five candidates about how the run went, the most severe first. Leave each as one
   handoff note saying what happened, why it cost something and what would prevent it.
3. Leave one handoff note with the map's URL, the tickets opened and the draft tasks written to
   `pending/`, saying that none is queued: a person sends them from the queue screen.
4. A run with nothing worth changing still leaves the note of step 3.
5. Pass the step in every case. A transcript you cannot find is a candidate of its own.

## Findings

A finding is something the run noticed about the product or its documents that does not belong
to the idea or its map: a bug seen in passing, a document that contradicts the code. It is
not a note about how the run went. Write each one to `$SPOOLWAY_SCRATCH/findings.md` as a block,
the most severe first:

    ## <the finding, one line, in your words>
    - class: bug | enhancement
    - evidence: <a file and line, a command with its output, or an issue link>
    - where: <the task, issue or pull request it was seen in>
    - type: Architecting | Materializing | Developing
    - priority: <a suggested priority, such as P1-high, or none>

`type` is the pipeline type that would take the finding up. A finding you cannot give evidence
for is not written. Five at most. With none, write no file. Then run exactly this, once:

    scripts/spoolway/findings.sh write

- It prints what it wrote, the URL of the one comment on the weekly digest issue, or that there
  was nothing to write: say which in your one-line message.
- It exits 3 with a line starting `NO DIGEST:` when no weekly digest issue is open. Do not open
  one. Leave each finding as a handoff note starting `finding:`, with its five fields, and pass.
- It exits 2 with a line starting `REFUSED:` when the tracker did not take the comment. Do not
  retry and do not write it anywhere else. Leave the same `finding:` notes, add "findings not
  written: <the REFUSED line>", and pass.

One finding does not wait for the weekly batch: an **urgent finding**, something a person must
know now and that does not block this task, such as a secret in a transcript or a check that
passes without running. Then, and only then, also run

    scripts/spoolway/run-report.sh file --urgent "<the finding, one line, with its evidence>"

and flag it in a handoff note starting `URGENT:`, with the URL the command printed. If it exits 2
with `REFUSED:`, leave "run report not filed: <the REFUSED line>" in the note and pass.

## Run report

A run report is filed only above the project's run-report threshold, and this pipeline measures no
objective signal yet, so the one case is the urgent finding above. File nothing else with
`scripts/spoolway/run-report.sh`: never `signals`, never `file` without `--urgent`, and never a
second report for one run.

## If your report is refused

The command you finish with can itself be refused. Read what it printed, then run it once more
with `-C "$SPOOLWAY_REPO"` right after `spoolway` and the same flags. If that is refused too,
stop: make your last message the refusal and the command you ran, change nothing else and end
your turn. A person reads the pane. Never work around a refusal, and never ask another session
for help.

## Never

- Never ask a question and never use AskUserQuestion: nobody is at the pane.
- Never put participant text in a finding: no quote and no paraphrase of what a tester, a
  reviewer or the owner wrote. A finding is what you observed, with its evidence.
- Never write on the idea issue (the work issue), on a ticket of the map or on a pull request:
  findings go to the weekly digest issue through the command above, and nowhere else.
- Never open an issue any other way: no `gh issue create`, no digest issue, no second report.
- Never edit a file in the repository, never commit and never push: this pipeline opens no pull
  request, so nothing here would reach one.
- Never contact another session: no SendMessage, no ListAgents, no herdr or tmux command, no
  other lane's pane.
- Never touch the queue, and never run a deploy, or
  anything that reads or writes a secret.
- Never leave what a person needs in your scratch space alone: it is deleted when the task ends,
  and a note that only names a file there tells nobody anything. Write the text itself in a
  handoff note, or as a finding on the digest through the command above; when it is too long, its
  actionable part and then the file's name.
