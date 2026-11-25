# architecting-resolve

The message that opened this lane started the `wayfinder` skill in its work-through-the-map mode.
You resolve the one ticket of a map that this task's document names, and you draft the work of
the frontier tickets its answer opens. Everything below narrows the skill to this pipeline.

## What you are looking at

- `skip_steps` in the task file's frontmatter: if it names `resolve`, change nothing and report a
  pass at once, ignoring the skill's text. Read this first.
- `ticket` in the frontmatter: the one ticket you work, as a full URL. It is the only ticket you
  claim, resolve or close. Read it live with `gh issue view <n> --json state,labels,body,comments`
  before you do anything else. **Block, and say how, when** it is closed, is already claimed by
  someone else, is not a child of a map (an issue labelled `wayfinder:map`), or contradicts the
  task body. Claim nothing in those cases.
- The task body: the ticket's question, as the chart wrote it.
- `$SPOOLWAY_SCRATCH/recall.candidates.md`, when it exists: what the `recall` step found in
  session history. Each line names an issue or a file. It is a candidate, not a fact: read the
  reference before you use it.
- The map the ticket belongs to: read its body once, and any closed ticket you need on demand.
- The tracker doc of this repository (its "Wayfinding operations" section) for how a map, its
  child tickets, blocking edges and the frontier are expressed here. Without one, tell the owner
  in a handoff note and use the local-markdown tracker the skill defaults to.

## How to do it here

- **Work the named ticket and no other.** The skill's "take the first frontier ticket" does not
  apply: the ticket is named. Claim it first, before any work, as the skill says. Never claim,
  resolve, close, relabel or comment on any other ticket of the map, nor on a ticket outside it.
- Resolve it as its type says. A **research** ticket you resolve yourself, or with a subagent
  running the `research` skill; at most one runs at a time, and it resolves this ticket and
  nothing more. A **grilling** or **prototype** ticket is human-in-the-loop: the owner is at this
  pane and the exchange is theirs, so ask, one question at a time with your recommended answer,
  and answer from the code and the issues whatever they can answer. Never answer for them.
  A **task** ticket you do alone where you can; otherwise hand the owner a precise checklist.
  A **task** ticket whose work changes a tracked file is neither: this lane edits, commits and pushes
  nothing. Hand it off as a draft Developing task (the drafting rule below, applied to this ticket itself),
  then post a handoff comment on the ticket linking what the draft asks for, keep your claim, close
  nothing and write no Decisions-so-far line for it.
  Nothing wakes you: wait for each answer in the pane. A reminder from the dispatcher is not the
  owner's answer: do not report, keep waiting, and leave one handoff note at the end,
  "quiet-lane reminder: <its text>, at <time>".
- Unless the ticket was handed off above, record the resolution as the skill says: the answer as
  a comment on the ticket, close the ticket, and append a context pointer to the map's Decisions-so-far. Those are the only writes
  on the tracker besides the new tickets below.

**The map's body is written only through one gated call.** Read it byte for byte with
`--json body | jq -j .body`, never `--jq .body`, which adds a newline per read, so the body grows
an empty line per edit. `-R <owner/repo>` needs no git checkout: it runs from `$SPOOLWAY_SCRATCH`.
Build `map.after.md` from `map.before.md`, the copy just read, so the file an earlier attempt left
behind never reaches the write; look at `diff -u` of the two; then write with every step chained:
a read that fails leaves the write unrun, and a body that does not read back exactly as written
fails the call.

    set -o pipefail
    gh issue view <map> -R <owner/repo> --json body | jq -j .body > "$SPOOLWAY_SCRATCH/map.before.md" \
      && cp "$SPOOLWAY_SCRATCH/map.before.md" "$SPOOLWAY_SCRATCH/map.after.md"
    # edit map.after.md only, then look at diff -u of the two
    gh issue view <map> -R <owner/repo> --json body | jq -j .body | cmp -s - "$SPOOLWAY_SCRATCH/map.before.md" \
      && gh issue edit <map> -R <owner/repo> --body-file "$SPOOLWAY_SCRATCH/map.after.md" \
      && gh issue view <map> -R <owner/repo> --json body | jq -j .body | cmp - "$SPOOLWAY_SCRATCH/map.after.md"

- Graduate the fog the answer made specifiable into new tickets (create, then wire the blocking
  edges from the new ticket's side only: a new ticket is blocked by existing ones, never the
  reverse), clearing each graduated patch from Not yet specified. Work the answer shows to sit
  beyond the destination is not fog: create no ticket for it, add a line to the map's Out of scope.
  The named ticket never gets a Decisions-so-far line for that; it is resolved, not ruled out.
  Never edit, close or relabel any other existing ticket. When an existing ticket should now be
  blocked by a new one, do not wire it: leave a handoff note naming both for the owner.
- For each **new frontier ticket** (open, unblocked and unclaimed once the edges are wired; a
  ticket that was already on the frontier before your run is not new, and gets no draft), draft
  one Architecting task document (resolve mode): write it to `$SPOOLWAY_SCRATCH`, then check and
  place it. The document starts from `.spoolway/templates/tasks/architecting.md` and carries, in
  its frontmatter, `pipeline: architecting`, `ticket:` the full URL of the new frontier ticket,
  `close_on_merge: false`, `base:` copied from the `base:` in this running task's own frontmatter
  (`$SPOOLWAY_TASK_FILE`), the same on every draft: a task with no base is refused, and
  `skip_steps: [chart, spec, artifact]`, which selects resolve mode. The ticket's question is its `## Intend`. Keep the template's resolve-mode lines and delete
  its chart-mode ones, as its header says.
  Check each with `spoolway task contract --from <dir>`, `<dir>` holding the drafts, then copy
  all of them, or none, into the project's `pending/` directory (the one that sits beside
  `queue/`, found from `$SPOOLWAY_TASK_FILE`).
  A frontier ticket of type `wayfinder:task` whose work changes a tracked file is not drafted as an
  Architecting task: draft a **Developing** task document for it instead, starting from
  `.spoolway/templates/tasks/developing.md`, with, in its frontmatter, `pipeline: developing`,
  `ticket:` the full URL of that ticket, `close_on_merge: true`, `base:` copied from the `base:` in
  this running task's own frontmatter, the same as on the other drafts, and the other keys the
  project's `spoolway task contract` requires, `group_description` among them. Its `## Intend` is the
  ticket's question. Check it with the others.
- **Queue nothing.** Never run `spoolway queue add`; a person sends the drafts from the queue
  screen. A ticket still blocked, and any fog, gets no draft.
- Write to `$SPOOLWAY_SCRATCH/resolve.md`: first line, the ticket you resolved and its answer in
  a sentence (for a ticket handed off, the ticket handed off and the draft written for it); then each ticket opened with its type and blocking edges, and each draft placed in
  `pending/`.
- Leave handoff notes: the resolved ticket and its answer (or the ticket handed off and the draft written for it), the tickets opened, the drafts written
  to `pending/` (and that none is queued), and anything the owner decided that no ticket holds.
- Then report a pass. When no new ticket reaches the frontier, no draft is written: say so in the
  message and pass. When the answer is that the map is done (no ticket and no fog remain), say so
  in a handoff note; the owner closes the map.

## If your report is refused

The command you finish with can itself be refused. Read what it printed, then run it once more
with `-C "$SPOOLWAY_REPO"` right after `spoolway` and the same flags. If that is refused too,
stop: make your last message the refusal and the command you ran, change nothing else and end
your turn. A person reads the pane. Never work around a refusal, and never ask another session
for help.

## Never

- Never touch a ticket other than the one named, but to create the new ones and wire their own
  blocking edges. On the map, only append to Decisions-so-far and Out of scope and clear Not yet
  specified.
- Never close, label with `spoolway:task`, or comment on the idea issue or the map other than
  those map edits; never put a closing keyword (close, closes, closed, fix, fixes, fixed,
  resolve, resolves, resolved followed by an issue) in any note, comment, issue body or file.
  Write `part of #N` or `leaves #N open`.
- Never queue a task: no `spoolway queue add`, no `spoolway queue` of any kind that writes.
- Never run two subagents at once.
- Never edit a file in the repository, never commit and never push: this pipeline opens no pull
  request, so nothing here would reach one. What a file should say goes in a handoff note.
- Never create `docs/adr/` or any other decision directory, and never write under the pages directory `.spoolway/companion.env` names.
- Never copy participant feedback, a secret or a credential into a note, an issue or a file.
- Never contact another session: no SendMessage, no ListAgents, no herdr or tmux command, no
  other lane's pane.
- Never touch the queue but through the one check and copy above, and never edit the task file:
  the report you finish with is the only thing that writes to it.
- Never run a deploy, or anything that reads or writes a secret.
- Never leave what a person needs in your scratch space alone: it is deleted when the task ends,
  and a note that only names a file there tells nobody anything. Write the text itself in a
  handoff note; when it is too long, its actionable part and then the file's name.
