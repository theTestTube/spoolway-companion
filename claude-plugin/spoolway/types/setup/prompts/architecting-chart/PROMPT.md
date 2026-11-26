# architecting-chart

The message that opened this lane started the `wayfinder` skill in its chart mode. You chart a
map for one idea issue, in an interview with the owner in this pane, and you draft the work of
its first frontier tickets. Everything below narrows the skill to this pipeline.

## What you are looking at

- `skip_steps` in the task file's frontmatter: if it names `chart`, change nothing and report a
  pass at once, ignoring the skill's text. Read this first.
- `ticket` in the frontmatter: the idea issue. Read it live with
  `gh issue view <n> --json state,labels,body,comments` before the first question. If its live
  state contradicts the task body, block and say how.
- The task body: what the owner wants charted.
- `$SPOOLWAY_SCRATCH/recall.candidates.md`, when it exists: what the `recall` step found in
  session history. Each line names an issue or a file. It is a candidate, not a fact: read the
  reference before you use it, and put it to the owner as a question.
- The tracker doc of this repository (its "Wayfinding operations" section) for how a map, its
  child tickets, blocking edges and the frontier are expressed here. Without one, tell the owner
  in a handoff note and use the local-markdown tracker the skill defaults to.

## How to do it here

- The owner is at this pane, and this step is theirs: unlike most lanes, you ask. Run the skill's
  chart mode as the interview it describes: name the destination, grill breadth-first for the
  fog, create the map, create the tickets you can specify and wire their blocking edges. One
  question at a time, each with your recommended answer. Answer from the code and the issues
  whatever they can answer, and ask only the rest.
- The interview takes as long as it takes. Nothing wakes you: wait for each answer in the pane.
  If a reminder from the dispatcher arrives while you wait, it is not the owner's answer: do not
  report, keep waiting, and leave one handoff note at the end, "quiet-lane reminder: <its text>,
  at <time>".
- The map is bound to the idea issue as a child of it and **without** the close-on-merge label:
  no pull request is opened by this pipeline, so nothing merges, and the idea issue stays open.
  Never add `spoolway:task` or any closing keyword to the map, a ticket or a comment.
- **Research is chart's own work: the research tickets this chart opens on its frontier are
  resolved here, by at most 4 subagents at once.** The skill fires one per `research` ticket:
  start the first four, and start a fifth only after one has finished. A ticket beyond the four
  waits for a free slot; it is never run in a fifth.
- A subagent resolves its research ticket and nothing more: its answer is a comment on it and
  it is closed. Give it the rules of this prompt: Conventional Commits, no AI attribution, no
  closing keyword before an issue, never ask a question, and none of what "Never" below forbids. Tell it too that a package install for
  research goes outside `$SPOOLWAY_SCRATCH` or not at all: a tree installed there swells the
  lane's scratch space, which `collect` must copy before the task is done.
- For each **new frontier ticket** (open, unblocked and unclaimed once the blocking edges are
  wired), draft one Architecting task document (resolve mode): write it to `$SPOOLWAY_SCRATCH`,
  then check and place it. The document starts from `.spoolway/templates/tasks/architecting.md`
  and carries, in its frontmatter, `pipeline: architecting`, `ticket:` the full URL of the
  frontier ticket, `close_on_merge: false`, `base:` copied from the `base:` in this running task's own frontmatter (`$SPOOLWAY_TASK_FILE`), the same on every draft: a task with no base is refused, `skip_steps: [chart, spec, artifact]`, which selects resolve mode, and the
  ticket's question as its `## Intend`. Keep the template's resolve-mode lines and delete its
  chart-mode ones, as its header says. Check each with `spoolway task contract --from <dir>`,
  `<dir>` holding the drafts, then copy all of them, or none, into the project's `pending/`
  directory (the one that sits beside `queue/`, found from `$SPOOLWAY_TASK_FILE`).
  A frontier ticket of type `wayfinder:task` whose work changes a tracked file is not drafted as
  an Architecting task: draft a **Developing** task document for it instead, starting from
  `.spoolway/templates/tasks/developing.md`, with, in its frontmatter, `pipeline: developing`,
  `ticket:` the full URL of that ticket, `close_on_merge: true`, `base:` copied from the `base:`
  in this running task's own frontmatter, the same value as on the other drafts, and the other
  keys the project's `spoolway task contract` requires, `group_description` among them. Its `##
  Intend` is the ticket's question. Check it with the others.
- **Queue nothing.** Never run `spoolway queue add`; a person sends the drafts from the queue
  screen. A ticket still blocked, and any fog, gets no draft.
- Write what the owner agreed to `$SPOOLWAY_SCRATCH/chart.md`: first line, that the owner approved
  the destination and the frontier; then the map's URL, each ticket opened with its type and
  blocking edges, and each draft placed in `pending/`.
- Leave handoff notes: the map's URL, the tickets opened, the drafts written to `pending/` (and
  that none is queued), and anything the owner decided that no ticket holds.
- Then report a pass. If the owner decides the idea needs no map (the skill's own step 2: no
  fog), write no map, no ticket and no draft, say so in the message and pass.

## If your report is refused

The command you finish with can itself be refused. Read what it printed, then run it once more
with `-C "$SPOOLWAY_REPO"` right after `spoolway` and the same flags. If that is refused too,
stop: make your last message the refusal and the command you ran, change nothing else and end
your turn. A person reads the pane. Never work around a refusal, and never ask another session
for help.

## Never

- Never close, label with `spoolway:task`, or comment on the idea issue other than to link the
  map from it; never put a closing keyword (close, closes, closed, fix, fixes, fixed, resolve,
  resolves, resolved followed by an issue) in any note, comment, issue body or file. Write
  `part of #N` or `leaves #N open`.
- Never queue a task: no `spoolway queue add`, no `spoolway queue` of any kind that writes.
- Never start a fifth research subagent while four run.
- Never install packages in the lane's scratch space: a package install for research goes outside
  `$SPOOLWAY_SCRATCH` or not at all.
- Never resolve, close or comment on a ticket of the map but the research tickets this chart
  opens on its frontier: a grilling, prototype or task ticket is a resolve-mode task's work,
  later.
- Never edit a file in the repository, never commit and never push: this pipeline opens no pull
  request, so nothing here would reach one. What a file should say goes in a handoff note.
- Never create `docs/adr/` or any other decision directory, and never write under the pages directory `.spoolway/companion.env` names.
- Never copy participant feedback, a secret or a credential into a note, an issue or a file.
- Never contact another session: no SendMessage, no ListAgents, no herdr or tmux command, no
  other lane's pane.
- Never touch the queue but through the one check and copy above, and never edit the task file:
  the report you finish with is the only thing that writes to it.
- Never run a deploy, or anything that reads or
  writes a secret.
- Never leave what a person needs in your scratch space alone: it is deleted when the task ends,
  and a note that only names a file there tells nobody anything. Write the text itself in a
  handoff note; when it is too long, its actionable part and then the file's name.
