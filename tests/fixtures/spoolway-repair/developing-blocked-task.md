---
id: dev-advance
title: 'chore(probe): leave one deliberate type error in a new file'
stage: blocked
last_report:
  step: implement-spec
  outcome: pass
  at: 1791496102
blocked_from: checks
pipeline: developing
group: dev-shape
group_description: Synthetic task with the shape of a Developing task parked on blocked by a refused route.
branch: task/dev-advance
base: develop
run: r0000000000000001
cut_from: develop
base_commit: @BASE_COMMIT@
worktree_path: @WORKTREE@
workspace_id: w90
pane_id: w90:p1
tab_id: w90:t1
steps:
  checks->implement: 2
  implement->implement-spec: 3
  implement-spec->checks: 3
  queued->extra-worktree: 1
  extra-worktree->implement: 1
rounds:
  checks->blocked: 1
  checks->implement: 2
  implement->implement-spec: 3
  implement-spec->checks: 3
  queued->extra-worktree: 1
  extra-worktree->implement: 1
arrivals:
  blocked: 1
  checks: 3
  implement: 3
  implement-spec: 3
  extra-worktree: 1
arrived_from: checks
close_on_merge: false
ticket: https://github.com/example/app/issues/401
---

## Context

- This is a synthetic task. Nothing it produces is merged.
- The run needs the `checks` step to fail, so the failing typecheck is the deliverable.

## Intend

Add one new file, `src/devAdvance.ts`, holding one line with a type error, commit it, and report a pass.

## Non-goals

Out of scope. Doing any of these is a review failure, not a bonus.

- repairing the type error
- touching any other file

## Acceptance criteria

- `src/devAdvance.ts` exists with exactly that line and is committed on this branch with a
  Conventional Commits subject.
- The typecheck fails, and its only error is in `src/devAdvance.ts`.
- No other file is changed, and the step reports a pass.

## References

- the input issue, named by `ticket:` in the frontmatter, read live

## Left for a person

- [ ] Everything after the block: the owner repairs or withdraws this task and tears it down.

## Status Log
- 2026-10-08 23:44 → `extra-worktree`
- 2026-10-08 23:44 → `implement`
- 2026-10-08 23:44 `implement`: no readable earlier `developing-implement` session on this task — opened fresh
- 2026-10-08 23:45 → `implement-spec`: added src/devAdvance.ts with the type error and committed it
- 2026-10-08 23:45 `implement-spec`: no readable earlier `developing-implement-spec` session on this task — opened fresh
- 2026-10-08 23:45 → `checks`: implement-spec skipped: implementer is absent, so the implement step did the work
- 2026-10-08 23:45 `checks` exited 2 — see @STATE@/commands/dev-advance · checks.log
- 2026-10-08 23:46 → `implement`
- 2026-10-08 23:46 → `implement-spec`: checks failed only on the type error the task intends; nothing changed
- 2026-10-08 23:46 → `checks`: implement-spec skipped again; nothing changed here
- 2026-10-08 23:47 `checks` exited 2 — see @STATE@/commands/dev-advance · checks.log
- 2026-10-08 23:47 → `implement`
- 2026-10-08 23:47 → `implement-spec`: checks failed again only on the type error the task intends; nothing changed
- 2026-10-08 23:48 → `checks`: implement-spec skipped; nothing changed here
- 2026-10-08 23:48 `checks` exited 2 — see @STATE@/commands/dev-advance · checks.log
- 2026-10-08 23:48 `checks` may not send this to `implement` a 4th time — `implement` has `loop: 3`; carrying on to `blocked`
- 2026-10-08 23:48 → `blocked`

## Handoff
- `implement` — The local typecheck ran without its dependencies, so its output was noise; the checks step must install first. The type error is on line 1 of src/devAdvance.ts.
