# What spoolway was observed to do

Observed on spoolway 0.6.0 (the sections below are 0.6.0's unless a heading names 0.19.0) with two throwaway tasks (2026-10-07), each read from outside the lanes, and with two more on 2026-10-15 (`spoolway 0.6.0`): `probe-10-a`, retreated and queued again, and `probe-10-b`, unqueued with every commit already on the remote. Observed once each: on another version, check before promising.

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

## The unqueue of a started task (spoolway 0.19.0)

What was run on 0.19.0: `spoolway queue unqueue --help` and `spoolway queue pause --help`, read-only (the fixtures `tests/fixtures/spoolway-repair/unqueue-help.txt` and `pause-help.txt` are their output, verbatim). No unqueue was run on 0.19.0 by this repository: every behaviour below is **taken from that help text and the release notes (0.18.0, 0.18.1, 0.19.0), not observed**. UNVERIFIED: a live unqueue of a started task on 0.19.0, and every row of the table that the help text does not state.

- `--force` is gone from `queue unqueue` (retired by 0.18.0): the help lists only `--json` and `--repo`. Any stopped task is unqueued with the bare command, and a `blocked` task needs no `queue pause`. A running task is refused, "naming the pause command to run first" (help text).
- A started task has "its worktree and its local `task/<id>` branch deleted whatever they hold, with no commit first, all or nothing" (help text). 0.6.0's `--force` recorded uncommitted work in a `wip(<task>): blocked` commit; 0.19.0 does not. Loose files and unpushed commits are lost unless they were committed and pushed before. The retreat therefore commits, pushes and checks the remote first (`repair.sh retreat`).
- It also takes "every task after it in its group" back to pending, and prints one line per task it moved and what it deleted.

| Item | After the unqueue on 0.19.0 | Source |
|---|---|---|
| Document | In the pending directory, "stripped of every reserved key" so `queue add --from` takes it again. Whether the arrival counts and the Status Log survive as on 0.6.0 is UNVERIFIED on 0.19.0. | help text; the rest 0.6.0 |
| Worktree | Deleted, whatever it holds. | help text |
| Uncommitted work | Lost. No commit is made. | help text |
| Local branch | Deleted, whatever it holds. | help text |
| Remote branch | Untouched (0.6.0: the unqueue pushes nothing). UNVERIFIED on 0.19.0. | 0.6.0 |
| Scratch space | Deleted (0.6.0). UNVERIFIED on 0.19.0. | 0.6.0 |
| Command-step logs | Left in place (0.6.0). UNVERIFIED on 0.19.0. | 0.6.0 |
| Tracker | No comment, and the in-progress label stays (0.6.0). UNVERIFIED on 0.19.0. | 0.6.0 |

The dispatcher refusal is also 0.6.0's: UNVERIFIED on 0.19.0, so the retreat keeps refusing while a dispatcher runs.

### What 0.6.0 did (historical)

On 0.6.0 the flag was `--force`: it recorded uncommitted work in one commit, subject `wip(<task>): blocked` (seen as `d74ce94 wip(probe-398-b): blocked`), kept a local branch that held commits no remote had, and deleted one the remote held in full (`probe-10-b`). That behaviour is retired; the retreat no longer expects any of it.

## A re-queue of a retreated document

`probe-10-a` was retreated on `blocked` with `implement` at 3 arrivals of `loop: 3`, and its document was queued again unchanged (`spoolway queue add --from <the pending document>`):

- After the unqueue the pending document still held `arrivals` (blocked 2, checks 4, implement 3, implement-spec 3, extra-worktree 1) and `blocked_from: checks`.
- `queue add` drops them: the queued document has `stage: queued`, `branch` set again, and no `arrivals`, `rounds`, `arrived_from`, `steps`, `blocked_from`, `resume` or last report. The old Status Log and Handoff stay in the body.
- The new run started with fresh counts: `→ extra-worktree`, then `→ implement` at arrival 1, with no refusal. It took three full implementer laps and parked again only at the fourth: "`checks` may not send this to `implement` a 4th time — `implement` has `loop: 3`; carrying on to `blocked`".
- The run reused the existing branch `task/probe-10-a` at its old tip `3cc85ee` rather than cutting a new one, though its new `base_commit` was the newer develop tip `552b1af`.

So a re-queue does not start with the loop already spent, and there is nothing to clear.

## After `done`

The scratch space, the command-step logs and the worktree are deleted. The transcripts, the system prompts and the archived document stay, and so does a local branch that holds commits no remote has.
