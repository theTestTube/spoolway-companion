---
id: dev-retreat
title: 'chore(probe): leave one deliberate type error in another new file'
stage: blocked
last_report:
  step: implement
  outcome: block
  at: 1791501168
blocked_from: implement
pipeline: developing
group: dev-shape
group_description: Synthetic task with the shape of a Developing task parked on blocked by its own lane.
branch: task/dev-retreat
base: develop
run: r0000000000000002
cut_from: develop
base_commit: @BASE_COMMIT@
worktree_path: @WORKTREE@
workspace_id: w91
pane_id: w91:p1
tab_id: w91:t1
steps:
  checks->implement: 2
  implement->implement-spec: 2
  implement-spec->checks: 2
  queued->extra-worktree: 1
  extra-worktree->implement: 1
rounds:
  checks->implement: 2
  implement->blocked: 1
  implement->implement-spec: 2
  implement-spec->checks: 2
  queued->extra-worktree: 1
  extra-worktree->implement: 1
arrivals:
  blocked: 1
  checks: 2
  implement: 3
  implement-spec: 2
  extra-worktree: 1
arrived_from: implement
close_on_merge: false
ticket: https://github.com/example/app/issues/401
---

## Context

- This is a synthetic task. Nothing it produces is merged.
- The run needs the `checks` step to fail, so the failing typecheck is the deliverable.

## Intend

Add one new file, `src/devRetreat.ts`, holding one line with a type error, commit it, and report a pass.

## Acceptance criteria

- `src/devRetreat.ts` exists with exactly that line and is committed on this branch.
- The typecheck fails, and its only error is in `src/devRetreat.ts`.
- No other file is changed, and the step reports a pass.

## References

- the input issue, named by `ticket:` in the frontmatter, read live

## Left for a person

- [ ] Everything after the block: the owner repairs or withdraws this task and tears it down.

## Status Log
- 2026-10-09 01:10 → `extra-worktree`
- 2026-10-09 01:10 → `implement`
- 2026-10-09 01:10 `implement`: no readable earlier `developing-implement` session on this task — opened fresh
- 2026-10-09 01:10 → `implement-spec`: added src/devRetreat.ts with the type error and committed it
- 2026-10-09 01:11 `implement-spec`: no readable earlier `developing-implement-spec` session on this task — opened fresh
- 2026-10-09 01:11 → `checks`: implement-spec is not the implementer for this task; nothing changed
- 2026-10-09 01:11 `checks` exited 2 — see @STATE@/commands/dev-retreat · checks.log
- 2026-10-09 01:11 → `implement`
- 2026-10-09 01:11 → `implement-spec`: nothing to change: checks fail only on the type error the task intends
- 2026-10-09 01:12 → `checks`: implement-spec is not the implementer here; nothing changed
- 2026-10-09 01:12 `checks` exited 2 — see @STATE@/commands/dev-retreat · checks.log
- 2026-10-09 01:12 → `implement`
- 2026-10-09 01:12 → `blocked`: checks fail only on the type error the task intends, and each pass from implement loops back here. Nothing left for this step to change.

## Handoff
- `implement` — The local typecheck ran without its dependencies; the checks step should see the single error after a real install.
- `implement` — The checks log confirms the single typecheck error is in src/devRetreat.ts; left unrepaired on purpose, per the task.
