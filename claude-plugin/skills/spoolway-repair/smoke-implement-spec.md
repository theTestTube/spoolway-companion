# Worked example: `smoke-implement-spec`

The task whose incident the skill answers (a smoke run, 2026-10-07). Developing pipeline, bound to a spec, `implementer: implement-spec`, `skip_steps: [implement]`. The replay in `tests/spoolway-repair.test.sh` runs the script on this document, cut back to the moment it stood on `blocked`.

## What diagnose concludes

- **Cause.** `implement` was refused entry to `implement-spec`: its `loop: 3` was spent at 3 arrivals. The task is parked on `blocked` from `implement`, the step that tried to forward.
- **Arrivals.** `implement` stands at 5 against a `loop` of 3, because a person's named resume is not checked against the loop but still counts an arrival. Name the step the refusal line names (`implement-spec`), not the first step over its loop.
- **Plain resume.** It goes to `blocked_from`, `implement`. That step passes at once, because the task names the other implementer and skips it, and forwards to `implement-spec`, whose loop is spent. The task bounces back to `blocked`: twice in the incident, at 07:42 and 07:43.
- **Criteria.** Of three, one can never pass: criterion 1 asks for every ticket of the spec to be built, and one ticket needs a triage and issues only a person may open. Criteria 2 and 3 read "UNVERIFIED" and "not met" in the review's notes and are passable.
- **Handoff.** Several notes ask a person to open an issue or post a table before the task ends. One names a notes file that only the scratch space held.
- **Dispatcher, keep-open.** The task carries `close_on_merge: false`; the marker is present.

## What salvage leaves

Every scratch file and command log under `.scratch/spoolway/smoke-implement-spec/`, and a draft per note that asks to post or open. In the incident none of this was done: `done` removed the worktree, the scratch space and the command logs, and a notes file the review had twice asked a person to post was lost with them.

## What choose concludes

- **Road.** Advance, on condition that the person amends criterion 1. Seven findings are open from the review's second lap: six the worktree can repair, and finding 7, for a person, which rests on criterion 1 and goes with its amendment.
- **Resume step.** `checks`, the first judgment downstream of `implement-spec`. `checks` passed on the last lap and `review` did not; both run again over the repair.

## What advance and the door conclude

- **The resume.** At `checks`, by name. A failure of `checks` or `review` routes to `implement`, whose loop is spent: the task parks again and no lane starts on the repair.
- **The extra lap.** Naming `implement-spec` would be its 4th arrival against a `loop` of 3.
- **The door.** `extra-handover`, `handover` and every step after them are past `review`, which has not passed. In the incident the task left by `--stage extra-handover` with nothing salvaged: the pull request went out with six findings unrepaired and no word of it, and they were repaired afterwards on its branch with no review of the repair.

## What record leaves

A comment for the bound issue, and two findings: the task-document defect (criterion 1 could never pass) and the pipeline defect (a plain resume crosses a pass-through step into a spent loop).
