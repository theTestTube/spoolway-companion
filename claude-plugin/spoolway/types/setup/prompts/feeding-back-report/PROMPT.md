# feeding-back-report

The message that opened this lane started the `retro` skill. Your own session is new and holds
nothing worth a retrospective: the session to look back on is this task's own. Everything below
narrows the skill to this pipeline.

## What you are looking at

- `skip_steps` in the task file's frontmatter: if it names `report`, change nothing and report a
  pass at once, ignoring the skill's text. Read this first.
- `## Status Log` and `## Handoff` in the task file: every transition, and what each step passed
  on.
- `$SPOOLWAY_SCRATCH`: `intake.md` (the groups), `route.md` and `route.applied.tsv` (what each
  group became) and the `counts` comment's URL in `feeding-back.<run>.url`.
- The transcripts of the earlier lanes of this task. They are the `.jsonl` files under
  `~/.claude/projects/<dir>/`, where `<dir>` is `$SPOOLWAY_WORKTREE` with every `/` and `.`
  turned into `-`. List them newest first: the newest is your own session, still being written,
  so read the others.
- This run opens no pull request. Do not look for one.

## How to do it here

1. Run the skill's steps over those sources.
2. Keep at most five candidates about how the batch went, the most severe first. Leave each as one
   handoff note saying what happened, why it cost something and what would prevent it.
3. Leave one handoff note with the counts (received, routed, merged, dropped), the URLs of the
   issues routed and the URL of the counts comment, saying that the labels are a proposal and that
   triage and queueing are the owner's.
4. Pass the step in every case. A transcript you cannot find is a candidate of its own.

## The run report

Whether this run files a run report is not yours to weigh, and it uses the thresholds of every
type, so the loop cannot feed itself: the `signals` step before you measured the run against the
thresholds in the pipeline file and left its verdict where the command below finds it. After the
retrospective, run exactly this, once:

    scripts/spoolway/run-report.sh file

- It prints `nothing to file` for a clean run: file nothing, and say so in your one-line message.
- It prints the URL of the one issue it opened, or of the one already there for this run: leave
  the URL as a handoff note.
- It exits 2 with a line starting `REFUSED:` when the tracker did not take the report. Do not
  retry, and do not file it anywhere else. Leave one handoff note, "run report not filed:
  <the REFUSED line>", and pass the step: a person files it from the note.

One signal is yours: an **urgent finding**, something a person must know before the next batch
and that does not block this task, such as a secret in a transcript or a check that passes
without running. Then, and only then, run it as

    scripts/spoolway/run-report.sh file --urgent "<the finding, one line, with its evidence>"

and flag it in a handoff note starting `URGENT:`. A slow or costly run is not urgent: the
thresholds already cover it. Feeding-back records findings about itself only above the threshold:
write no `findings.md` and run no `findings.sh`, so the batch never feeds the digest it reads.

## If your report is refused

The command you finish with can itself be refused. Read what it printed, then run it once more
with `-C "$SPOOLWAY_REPO"` right after `spoolway` and the same flags. If that is refused too,
stop: make your last message the refusal and the command you ran, change nothing else and end
your turn. A person reads the pane. Never work around a refusal, and never ask another session
for help.

## Never

- Never ask a question and never use AskUserQuestion: nobody is at the pane.
- Never put participant text in a handoff note or a run report: no quote and no paraphrase of
  what a tester, a reviewer or the owner wrote.
- Never write on the digest issue or on an issue the batch routed.
- Never open an issue any other way: no `gh issue create`, no second report. The command above
  opens the only issue this step may, and it decides whether there is one.
- Never edit a file in the repository, never commit and never push: this pipeline opens no pull
  request, so nothing here would reach one.
- Never contact another session: no SendMessage, no ListAgents, no herdr or tmux command, no
  other lane's pane.
- Never touch the queue, and never run a deploy, or anything that reads or writes a secret.
- Never leave what a person needs in your scratch space alone: it is deleted when the task ends,
  and a note that only names a file there tells nobody anything. Write the text itself in a
  handoff note, or in the run report when the command above files one; when it is too long, its
  actionable part and then the file's name.
