# What spoolway was observed to do

Observed on spoolway 0.6.0 with two throwaway tasks (2026-10-07), each read from outside the lanes, and with two more on 2026-10-15 (`spoolway 0.6.0`): `probe-10-a`, retreated and queued again, and `probe-10-b`, unqueued with every commit already on the remote. Observed once each: on another version, check before promising.

## A named resume

- A plain resume goes to the step the task was blocked from, whatever failed there.
- `spoolway queue list` shows beside `[r]` where a pass of the blocked step leads, not where a resume lands: the step after it for an agent step (seen for a task blocked from `review`, and for one blocked from `implement`), the step itself for a command step (seen for `checks`). The landing on the blocked step is the binary's own word, "resumes the step it stopped on". UNVERIFIED: a plain resume of a task blocked from an agent step, watched live.
- A resume that names a step is admitted even when that step's loop is spent: the loop guards a step's routing into a spent step, not a person's choice. The arrival is still counted.
- Resuming at the judgment downstream of the implementer moves only that judgment's count and spends no implementer arrival. A command step with no `loop` can be resumed at any number of times.
- When the judgment fails again, its route into the spent implementer is refused and the task parks on `blocked`. No lane starts on the repair.
- Naming the spent implementer buys one more lap. The lane continues the implementer's earlier session, where the step keeps a session and was visited before.
- A block that comes from a refused route holds no lane: the lanes had reported and exited. The repair is the person's, or that extra lap.
- UNVERIFIED, an accepted known limit (owner decision, 2026-10-13): an agent judgment failing after a named resume. Only a command step was made to fail; the refusal is the same mechanism, so the same parking is expected.
- UNVERIFIED: a block a lane reports itself, where a session is held.

## The forced unqueue of a started task

It is refused while a dispatcher runs, naming its pid. Without the force flag it is refused on a started task and changes nothing.

| Item | After the forced unqueue |
|---|---|
| Document | In the pending directory, gone from the queue, not archived. The keys of the run are stripped (`stage`, `run`, `branch`, `cut_from`, `base_commit`, `worktree_path`, workspace and pane ids); `base`, the last report, `blocked_from`, `resume`, the arrival and round counts, `arrived_from`, `steps`, and the body with its Status Log and Handoff are kept. The task contract accepts it as it is. |
| Worktree | Removed. |
| Uncommitted work | Tracked and untracked files alike, in one commit on the local branch, subject `wip(<task>): blocked` (seen as `d74ce94 wip(probe-398-b): blocked`). Not a project commit type: it is to be rewritten by hand before a merge. With a clean tree no commit is made. |
| Local branch | Kept when it holds commits no remote has, ahead of the remote by the unqueue's commit if there is one; the unqueue says so: "kept branch `task/probe-10-a` — it has commits no remote has". Deleted, with no line saying so, when the tree is clean and the remote already holds every commit (`probe-10-b`: the output was only "removed worktree …" and "unqueued `probe-10-b` → …/pending/probe-10-b.md"; `task/probe-10-b` gone locally, still on the remote at `1bc98e3`; seen again on the second retreat of `probe-10-a`, whose branch the first retreat had pushed). |
| Remote branch | Untouched: the unqueue pushes nothing. |
| Scratch space | Deleted. |
| Command-step logs | Left in place. |
| Lane sessions | The workspace is closed; the transcripts and system prompts remain. |
| Tracker | No comment on the ticket, and the in-progress label stays on it. |

## A re-queue of a retreated document

`probe-10-a` was retreated on `blocked` with `implement` at 3 arrivals of `loop: 3`, and its document was queued again unchanged (`spoolway queue add --from <the pending document>`):

- After the unqueue the pending document still held `arrivals` (blocked 2, checks 4, implement 3, implement-spec 3, extra-worktree 1) and `blocked_from: checks`.
- `queue add` drops them: the queued document has `stage: queued`, `branch` set again, and no `arrivals`, `rounds`, `arrived_from`, `steps`, `blocked_from`, `resume` or last report. The old Status Log and Handoff stay in the body.
- The new run started with fresh counts: `→ extra-worktree`, then `→ implement` at arrival 1, with no refusal. It took three full implementer laps and parked again only at the fourth: "`checks` may not send this to `implement` a 4th time — `implement` has `loop: 3`; carrying on to `blocked`".
- The run reused the existing branch `task/probe-10-a` at its old tip `3cc85ee` rather than cutting a new one, though its new `base_commit` was the newer develop tip `552b1af`.

So a re-queue does not start with the loop already spent, and there is nothing to clear.

## After `done`

The scratch space, the command-step logs and the worktree are deleted. The transcripts, the system prompts and the archived document stay, and so does a local branch that holds commits no remote has.
