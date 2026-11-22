---
id: live-401-retreat
title: 'chore(probe): leave one deliberate type error for the #401 live retreat'
stage: blocked
last_report:
  step: implement
  outcome: block
  at: 1791501168
blocked_from: implement
pipeline: developing
group: live-401
group_description: Throwaway tasks of issue 401, parked on blocked on purpose so spoolway-repair can be shown advancing one and retreating the other. Never merged.
branch: task/live-401-retreat
base: develop
run: r99cece3b75a7a112
cut_from: develop
base_commit: @BASE_COMMIT@
worktree_path: @WORKTREE@
workspace_id: w4M
pane_id: w4M:p1
tab_id: w4M:t1
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

- This is a throwaway task (issue 401). Nothing it produces is merged.
- The run needs the `checks` step to fail, so the failing typecheck IS the deliverable of this task.
- The implementer prompt asks you to run the typecheck as you go. Here a red typecheck on the one new file is the expected, correct result: do not repair it, do not block because of it.
- A person repairs or withdraws the task afterwards, from outside the lanes, with the `spoolway-repair` skill.

## Intend

Add exactly one new file, `src/live401Retreat.ts`, whose whole content is the single line `export const live401Retreat: number = 'deliberate type error for the #401 live retreat';`, commit it, and report a pass. `pnpm run typecheck` then fails on that line, and that is what this task is for.

## Non-goals

Out of scope. Doing any of these is a review failure, not a bonus.

- repairing, suppressing or working around the type error (`@ts-expect-error`, `any`, a cast, a tsconfig exclude)
- touching any other file
- blocking the task because the typecheck is red
- anything not required by the acceptance criteria below

## Acceptance criteria

- `src/live401Retreat.ts` exists with exactly the line above and is committed on this branch with a Conventional Commits subject.
- `pnpm run typecheck` fails, and its only error is in `src/live401Retreat.ts`.
- No other file is changed, and the step reports a pass.

## References

- the input issue, named by `ticket:` in the frontmatter, read live

## Left for a person

- [ ] Everything after the block: the owner repairs or withdraws this task with `spoolway-repair` and tears it down.

## Status Log
- 2026-10-09 01:10 → `extra-worktree`
- 2026-10-09 01:10 → `implement`
- 2026-10-09 01:10 `implement`: no readable earlier `developing-implement` session on this task — opened fresh
- 2026-10-09 01:10 → `implement-spec`: Added src/live401Retreat.ts with the deliberate type error and committed it
- 2026-10-09 01:11 `implement-spec`: no readable earlier `developing-implement-spec` session on this task — opened fresh
- 2026-10-09 01:11 → `checks`: implement-spec not the implementer for this task (implementer absent = implement); nothing changed
- 2026-10-09 01:11 `checks` exited 2 — see @STATE@/commands/live-401-retreat · checks.log
- 2026-10-09 01:11 → `implement`
- 2026-10-09 01:11 → `implement-spec`: Nothing to change: checks fail only on src/live401Retreat.ts(1,14) TS2322, the deliberate error
- 2026-10-09 01:12 → `checks`: implement-spec is not the implementer here (implementer absent = implement); nothing changed
- 2026-10-09 01:12 `checks` exited 2 — see @STATE@/commands/live-401-retreat · checks.log
- 2026-10-09 01:12 → `implement`
- 2026-10-09 01:12 → `blocked`: Checks fail only on the deliberate error in src/live401Retreat.ts (TS2322), and each pass from implement loops back here via implement-spec. Nothing left for this step to change; needs spoolway-repair by the owner.

## Handoff
- `implement` — In this worktree node_modules is missing, so my local typecheck was red from unrelated environment errors (the shared tsconfig base not found, lib targets); I did not confirm the only error is in src/live401Retreat.ts. The checks step should see it after a real install.
- `implement` — Checks log confirms the single typecheck error is in src/live401Retreat.ts; left unrepaired on purpose, per the task.
