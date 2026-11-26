# architecting-spec

The message that opened this lane started the `to-spec` skill. You publish the spec of a map
whose tickets are closed. Everything below narrows the skill to this pipeline: the skill
synthesizes from a conversation, and you have none.

## What you are looking at

- `skip_steps` in the task file's frontmatter: if it names `spec`, change nothing and report a
  pass at once, ignoring the skill's text. Read this first.
- `ticket` in the frontmatter: the map to publish, as a full URL. Read it live with
  `gh issue view <n> --json state,labels,body,comments` before you do anything else. **Block, and
  say how, when** it is closed, is not a map (an issue labelled `wayfinder:map`), or contradicts the
  task body.
- The map's "Decisions so far", "Out of scope" and "Not yet specified" sections, and the child
  tickets it links. Read every child ticket live, with its comments.
- The tracker doc of this repository (its "Wayfinding operations" section) for how a map, its
  child tickets and the triage labels are expressed here.
- `$SPOOLWAY_SCRATCH/recall.candidates.md`, when it exists, is a candidate list and not a source:
  the spec does not rest on it.

## How to do it here

- **Build only from the tracker.** You own no ticket and resolve none: the mode table in
  `.spoolway/templates/tasks/architecting.md` gives spec mode the map's closed tickets to cite and
  nothing to resolve. The sources are the map's "Decisions so far" and each closed ticket's
  resolution comment. Nothing from this conversation, from session history, from memory
  or from your own opinion is a decision. Where the tickets say nothing, the spec says nothing: put
  the gap under Further Notes.
- **Block, and say which, when a ticket the spec needs is still open**, or when the map's
  "Not yet specified" still holds fog the destination needs. Publish nothing in that case. A ticket
  recorded under Out of scope is not needed.
- **Re-decide nothing.** Every Implementation Decision is a decision a closed ticket already made,
  stated as it made it. When two closed tickets conflict, or a resolution is unclear, do not pick:
  block and name both.
- **Cite each closed ticket the spec rests on**, by `owner/repo#N`, beside the decision it
  supports. Add a `## Decisions cited` list at the end of the spec with every ticket you cited,
  one line each. A ticket that is closed and cited by nothing is named in a handoff note.
- Follow the skill's template. The skill's interview steps do not apply: do not ask the owner for
  anything, nobody is at the pane. Where it says to check the seams with the user, take a seam only
  from what a closed ticket decided; a seam no ticket decided goes under Further Notes, like any other gap.
- Publish the spec as a new issue in this repository's tracker, in the shape the tracker doc
  gives, with the triage label it names for work ready for an agent. Link it to the map with
  `part of #N`. Leave the map and every child ticket as they are: no comment, no label, no close.
- Write to `$SPOOLWAY_SCRATCH/spec.md`: first line, the URL of the spec; then the tickets cited.
- Leave handoff notes: the spec's URL, the closed tickets it cites, and each seam a ticket decided.
- Then report a pass. This pipeline opens no pull request.

## If your report is refused

The command you finish with can itself be refused. Read what it printed, then run it once more
with `-C "$SPOOLWAY_REPO"` right after `spoolway` and the same flags. If that is refused too,
stop: make your last message the refusal and the command you ran, change nothing else and end
your turn. A person reads the pane. Never work around a refusal, and never ask another session
for help.

## Never

- Never build the spec from a conversation, from memory or from a ticket that is still open.
- Never edit, close, relabel or comment on the map or on any ticket of it. The spec is the only
  issue you create.
- Never put a closing keyword (close, closes, closed, fix, fixes, fixed, resolve, resolves,
  resolved followed by an issue) in any note, comment, issue body or file. Write `part of #N`
  or `leaves #N open`.
- Never open a pull request, edit a file in the repository, commit or push.
- Never queue a task: no `spoolway queue add`, no `spoolway queue` of any kind that writes.
- Never create `docs/adr/` or any other decision directory, and never write under the pages directory `.spoolway/companion.env` names.
- Never copy participant feedback, a secret or a credential into a note, an issue or a file.
- Never contact another session: no SendMessage, no ListAgents, no herdr or tmux command, no
  other lane's pane.
- Never edit the task file: the report you finish with is the only thing that writes to it.
- Never run a deploy, or anything that reads or writes a secret.
- Never leave what a person needs in your scratch space alone: it is deleted when the task ends,
  and a note that only names a file there tells nobody anything. Write the text itself in a
  handoff note; when it is too long, its actionable part and then the file's name.
