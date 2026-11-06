<!--
An Architecting task is bound to an idea issue in chart mode, to one open ticket of a map in
resolve mode, or to a map whose tickets are closed in spec mode, and that issue outlives the task. The frontmatter must carry

  pipeline: architecting
  ticket: https://github.com/<owner>/<repo>/issues/<n>   the idea issue in chart mode, the one map ticket in resolve mode, the map in spec mode, as a full URL
  base: <the repository's default branch>               copy it from the running task's own base:; a task with no base is refused
  close_on_merge: false                                  the map is bound without the close-on-merge label
  skip_steps: [...]                                      picks the mode: [resolve, spec] is chart mode, [chart, spec, artifact] is resolve mode, [recall, chart, resolve] is spec mode

The body below is written per mode: each [[...]] marked chart, resolve or spec is kept for that
mode only, and the other modes' lines are deleted.

The pipeline opens no pull request and the worktree is removed at done. Delete this comment.
-->

## Context

Three to five facts, one line each. A lane cannot read the conversation that produced this task,
so this is where its ground goes: facts and names, not argument.

- [[what the idea asks for, in one line; spec mode: what the map is for]]
- [[what is already decided, and where: an issue, a file]]
- [[chart mode: what the owner wants settled in the chart]] [[spec mode: the map is complete and its tickets are closed]]

## Intend

[[What this run achieves: a wayfinder map charted for the idea, with a draft resolve-mode task in
`pending/` for each new frontier ticket.]] [[spec mode: a spec published from the map's Decisions so far and its closed tickets' resolution comments.]]

## Non-goals

Out of scope. Doing any of these is a review failure, not a bonus.

- [[chart mode: resolving a ticket of the map, which is a resolve-mode task's work]]
- [[resolve mode: resolving, closing or commenting on any other ticket of the map]]
- queueing a draft task: a person sends the drafts from the queue screen
- [[chart and spec modes: sharing or publishing the map's overview page beyond its private link, or putting anything on it the tickets do not say]]
- [[spec mode: re-deciding a question, or resting on anything but the map and its closed tickets]]
- [[the part of the idea this run leaves alone]]

## Acceptance criteria

- [[chart mode: the owner agreed the destination and the frontier in the chart.]]
- [[resolve mode: the named ticket is resolved as its type says, its answer is a comment on it, and it is closed.]]
- [[chart mode: the map is open on the tracker and bound to the idea issue without the close-on-merge label.]]
- [[chart and resolve modes: every new frontier ticket has a draft resolve-mode task in `pending/`, and none is queued.]]
- [[spec mode: the spec cites each closed ticket it rests on, re-decides none, and leaves the map and its tickets unedited, but for the one Notes line that links the overview page (and the Notes heading, when the map has none).]]
- [[chart and spec modes: the map's overview page is private and in English, follows the tickets and decides nothing, and its link is in the map's Notes (an existing page is updated in place, not duplicated).]]
- [[chart mode: research ran at most four subagents at a time.]] [[resolve mode: research ran one subagent at a time.]]
- [[chart mode: the idea issue is open when the task ends.]] [[resolve mode: no existing ticket of the map but the named one was edited, closed or commented on.]]

## References

Read these before you start. A path here replaces a paragraph above.

- the issue named by `ticket:` in the frontmatter (the idea issue, the map ticket, or the map), read live
- [[path or issue — why it matters]]

## Left for a person

A lane never attempts these.

- [ ] [[chart mode: the chart, where the owner answers the interview in the lane's pane]] [[resolve mode: a grilling or prototype ticket, where the owner answers in the lane's pane]]
- [ ] Sending the draft tasks from the queue screen
- [ ] Closing the idea issue, once its map is done (chart mode)
