<!--
A Materializing task is bound to a spec, and the spec outlives it. The frontmatter must carry

  pipeline: materializing
  ticket: https://github.com/<owner>/<repo>/issues/<n>   the spec, as a full URL
  close_on_merge: false                                  a spec is never closed by a merge (#316)
  base: <the branch this project lands in>               every draft copies it, so it is never guessed

The `bind` step refuses the task without the two middle lines. docs/spoolway-materializing.md
has every key. Delete this comment.
-->

## Context

Three to five facts, one line each. A lane cannot read the conversation that produced this task,
so this is where its ground goes: facts and names, not argument.

- [[what the spec asks for, in one line]]
- [[what is already decided, and where: an issue, a page]]
- [[what the owner wants settled in the grill]]

## Intend

[[What this run achieves: the spec grilled, triaged and cut into tickets, with a draft Developing
task per ticket, and one pull request recording what the grill decided.]]

## Non-goals

Out of scope. Doing any of these is a review failure, not a bonus.

- building anything the spec describes: that is the tickets' work
- queueing a draft task: a person sends the drafts from the queue screen
- [[the part of the spec this run leaves alone]]

## Risks

What could go wrong with this change, and what this task does about each. Drop
this heading if the task carries none.

- [[what could go wrong]]
  Mitigation: [[what this task does about it]]

## Acceptance criteria

- The owner approved the breakdown in the grill.
- Every ticket of the breakdown is open in its project's repository, a sub-issue of the spec.
- Every ticket of this project has a draft Developing task in `pending/`, and none is queued.
- Every decision and glossary term of the grill is in one open pull request, as `CONTEXT.md`
  entries and, when `.spoolway/companion.env` names a pages directory, pages, with the gates green; or the grill decided nothing and there is none.
- The spec is open when the task ends.

## References

Read these before you start. A path here replaces a paragraph above.

- the spec, named by `ticket:` in the frontmatter, read live
- what a command step printed (`bind`, `backing`, `drafts`, `gates`, `handover`, `pin`): never the
  Status Log, always `commands/<task id> · <step>.log` in the directory that holds this project's
  `queue/`. It is deleted with the scratch space when the task ends, so anything kept only there
  is copied into a handoff note before the last step
- [[path or issue — why it matters]]

## Left for a person

A lane never attempts these.

- [ ] The grill: the owner answers it in the lane's pane, then resumes the task from the board
- [ ] Reviewing and merging the documentation pull request; the merge leaves the spec open
- [ ] Sending the draft tasks from the queue screen
- [ ] Drafting a task, in its own project, for each ticket of the backend or the plugin
- [ ] Opening the week's digest issue, titled "Weekly digest ...", until Feeding-back exists
- [ ] Closing the spec, once its tickets are done
