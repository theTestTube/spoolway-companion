---
name: spoolway-repair
argument-hint: <task-id>
disable-model-invocation: true
---

# spoolway-repair

A person starts this when a spoolway task is **doomed**: parked on `blocked` with no route of its own to `done`. It reads the task from outside the lanes, **salvages** what cleanup would destroy, then takes one of two roads with the person: **advance** to `done` through a repair that is judged again, or **retreat**, undoing the run while keeping what it built. Any move that reaches `done` is a **one-way door**.

`<task>` is the task id given with the command. `repair.sh` sits beside this file; run it as `bash <this skill's base directory>/repair.sh <subcommand> <task>`, from the repo whose spoolway project holds the task. It prints one JSON object; a refusal exits 1 with `refused` saying why, and prints no command. A task spoolway does not hold is such a refusal, `unknown-task`, from every subcommand: say so and stop. A call the script cannot read at all (a malformed task id, a step the pipeline lacks, a repo with no spoolway project) prints one line on stderr and no JSON, and exits 2. Salvage has stops of its own, given in step 2. Spoolway's formats are read from the binary (`spoolway task contract`, `spoolway pipeline contract`, `--help`); take them from there, and from the script's output.

**The person's word** is a yes, in this session, to the exact command or draft you have just shown. Each resume, unqueue, push, comment and issue needs its own. Your own writes are the salvage folder and commits in the task's worktree; the dispatcher, the queue, pipelines, prompts and the tracked config stay the person's, and a defect in them becomes a finding (step 6).

What spoolway 0.6.0 was observed to do on each road sits in [observed.md](observed.md). Read it before you tell the person what a resume or an unqueue will leave behind, and whenever `spoolway --version` is not 0.6.0: what it lists is then to be checked, not promised.

A worked example, a task doomed twice over, sits in [smoke-implement-spec.md](smoke-implement-spec.md). Read it when a diagnosis looks unlike the plain case, or to compare your conclusions with a known one.

## 1. Diagnose

Read-only: write nothing, resume nothing, post nothing. Run `repair.sh diagnose <task>`.

Done when you have stated each of these, one line apiece, from the JSON:

- the stage, and the step it stopped from (`blocked_from`)
- every step's arrivals against its `loop`, and the last refusal line of the status log (`loops`, `last_refusal`). Where `loop_in_force` and `loop_in_refusal` differ, give both: the refusal line's is the one the dispatcher applied (`dispatcher_applied`), and `loop` is that one.
- where a plain `spoolway resume <task>` routes: the steps it crosses, and whether it bounces back to `blocked` (`plain_resume`). `spoolway queue list` can name another step beside `[r]`; [observed.md](observed.md) says what that one is.
- every handoff note addressed to a person, each with what it asks (`handoff.to_person`), listed in full
- each acceptance criterion, passable or not, with the reason (`criteria`). The script applies one narrow rule: a note cites the criterion and says only a person can act on it. Re-read the notes; where the rule misses an unpassable criterion or marks a passable one, say so and rule it yourself.
- the branch's commits since its base, its working-tree state, and whether the remote has them (`git`)
- every scratch file and every command-step log, by name and size (`scratch`, `commands`)
- whether a dispatcher is running, attended or unattended (`dispatcher`). An unattended dispatcher can start a lane on the task while the person works: say so, and ask the person to stop it; stopping it is theirs.
- for a task bound to a spec, its keep-open marker (`spec`). A bound task whose marker is `missing` would close the spec at merge: say so.

It ends on the **cause in one sentence**, with its evidence: `cause.sentence` and `cause.evidence`, or your own sentence where the evidence says the script got it wrong. A cause of kind `stopped-by-step` carries no refused route; read the step's last handoff note and the log line before naming it.

## 2. Salvage

The first write, and the only one: nothing else is written before it is complete. Run `repair.sh salvage <task>` once the diagnosis stands.

It copies every scratch file and every command-step log to `<main checkout>/.scratch/spoolway/<task>/`, under `scratch/` and `commands/`; the folder must be git-ignored, or the step stops before writing. While the task stands on `blocked` it keeps the diagnosis beside them as `first-diagnosis.json` (`first_diagnosis.state` is `written`); a salvage run after the task has moved on leaves that file as it is (`kept`), so the record of step 6 carries the cause as it was diagnosed here. It drafts, under `drafts/`, one file per handoff note that asks a person to post or open something. A draft is text for the person to review; posting and opening are theirs, in this session, on their word.

Done when the JSON says `ok` and you have shown the person:

- every copy, source to destination, each marked as matching by name and size (an empty list is a pass: say the scratch space was empty)
- every draft, with its path and the note it came from

A non-zero exit, or `ok: false`, stops the work. A folder that is not git-ignored exits 3 with one line on stderr, before any write. A copy that failed or differs exits 1 with `ok: false`: name the failing file from `failed`. A file whose name holds a tab or a newline exits 1 with one line that names it. Leave the task as it is, and tell the person. Run it again after the cause is cleared; a second run copies the same files to the same places.

## 3. Choose

Run `repair.sh choose <task>`. **Advance** when every open finding can be repaired in the worktree and every acceptance criterion can pass, or the person amends the ones that cannot; otherwise **retreat**.

Done when you have stated, from the JSON, and the person has ruled in words:

- the recommended road and its reason (`recommendation.road`, `recommendation.reason`), and the other road
- each condition of an advance (`recommendation.conditions`): a criterion the person must amend, a keep-open marker the person must restore
- the open findings, those the worktree can repair and those for a person (`findings`). The script reads two narrow shapes: a failed judgment that is a command step, one finding with its log (`kind: "command-step"`, `log`), and the `Finding <n>` notes a failed judgment left after the implementer's last note. Re-read the handoff and the log; where it misses a finding or counts a settled one, say so and rule it yourself.
- the step an advance resumes at (`resume_step`) and which judgments passed (`judgments`)

Wait for the ruling. The person may rule against the recommendation; take their road.

## 4. Advance

Repair each open finding in the task's worktree (`git.worktree.path` of the diagnosis) and commit there, under that repository's commit rule. A task parked by a spent loop holds no lane: the repair is yours with the person.

Then run `repair.sh advance <task>`. It proposes a resume at the first judgment downstream of the implementer, so every judgment the repair touches runs again. Before anything runs, show the person:

- the command (`shown`) and the status-log message it carries (`message`), checked against `spoolway resume --help`. It names its step: a plain resume goes to the step the task was blocked from.
- what a failure does (`on_failure`): where `parks` is true, a judgment that fails again parks the task on `blocked` and starts no lane on the repair. This was observed for a command step; for an agent judgment it is expected, not observed, and you say so.
- the extra implementer lap (`extra_lap`), as a choice with its count: arrival `arrival_would_be` against a `loop` of `loop`. It is proposed only when the person names it: `repair.sh advance <task> <extra_lap.step>` prints that command.

Run the command on the person's word. Done when every finding the person ruled repairable has a commit in the worktree, the person has seen the three items above, and the resume has run on their word or they have declined it. After a resume, run `repair.sh diagnose <task>` once the step ends and state the stage.

On `refused`, give the reason and run nothing. `keep-open-marker-missing` means the task is bound to a spec and a merge would close it: the marker is the person's to restore, and no handover is reachable until it is back.

### The one-way door

`repair.sh advance <task> <step>` with a step past a judgment that has not passed answers `kind: "one-way-door"` and no command. Tell the person which judgments the step skips (`door.past`) and how many findings stay open (`findings_open`), and that nothing past that step can be judged afterwards.

The door opens on two things together: salvage is complete (`door.salvage_complete`; run step 2 again if not), and the person says in words that they leave by the door. Pass their words: `repair.sh advance <task> <step> --confirmed "<their words>"`. The command then appears, and `drafts` holds a pull request section: the open findings as a checklist, under a heading that says the work came out of a repair by that door.

Done when the resume has run on the person's word and, once the handover has opened the pull request, that section is in its body, added on their word (`gh pr edit --help`).

`kind: "skips-judgment"` is a step past a judgment that passed before the repair: say which judgment will not run over the repair, and let the person rule.

## 5. Retreat

Run `repair.sh retreat <task>`. It is refused while a dispatcher runs (`dispatcher-running`: ask the person to stop it; stopping it is theirs) and while salvage is incomplete (run step 2 again).

Before the unqueue, tell the person what it leaves and what it destroys, from `expect` and from [observed.md](observed.md): the worktree and the scratch space go, the command logs stay, the in-progress label stays on the ticket, and the document goes back to the pending directory with its arrival counts kept. A re-queue of that document starts with fresh counts (`queue add` drops them) and carries on from the branch as it stands; say so, and do not offer to clear the counts.

What happens to the branch is `expect.branch.fate`:

- `kept-with-wip`: uncommitted work lands in one local commit under the subject `expect.uncommitted.commit`, `wip(<task>): blocked`. Say, before the push, that this commit must be rewritten to one of the project's commit types before the branch is merged by hand, and that you never rewrite, amend or squash it: that is the person's.
- `kept`: a clean tree with commits no remote has; the branch stays and is pushed. Nothing about a commit is said.
- `deleted`: a clean tree the remote already holds in full; the unqueue deletes the local branch, and `steps` has no push.

Then take `steps` in order, each on the person's word:

1. `comment`: show the draft of what was built and what was left (`left`; with no numbered finding it names the judgment that failed, and a section with nothing to list says so); the person posts it on the bound issue, or has you post it (`gh issue comment --help`).
2. `unqueue`: show `shown`, checked against `spoolway queue unqueue --help`, and run it.
3. `push`, when the branch is kept: first name the unqueue's commit when there is one (`git log -1 --format='%h %s' <branch>`, its subject `wip(<task>): blocked`) with the step's `warning`, then show `shown` and run it. This push is the one that counts: it carries that commit.
4. `verify`: run `repair.sh pushed <task>`.
5. `unlabel`: the in-progress label is taken off the ticket by hand; read its name from the ticket's labels.

Done when `repair.sh pushed <task>` says `ok` (the remote branch holds every commit of the local one, or, the local branch deleted, the remote stands at the tip the first diagnosis saw), `pending_document.present` is true, and the person has been told about the label and, when `wip_commit` is set, about that commit.

## 6. Record

Run `repair.sh record <task> <advance|retreat|door>` with the road taken. It writes drafts and posts nothing.

The cause and its evidence come from `first-diagnosis.json` of the salvage folder (`cause.source`), whatever the task's stage is by now: after a resume, after `done`, after the forced unqueue. `no-first-diagnosis` means the task has moved on and no salvage ran while it stood on `blocked`: write the cause yourself, from the status log. For an advance or the door the comment also names the repair's commits (`repair`), the resume line of the status log and the stage reached (`outcome`), as far as the task document shows them; where it says a thing is not readable or not shown, fill it in from what you saw or leave it said. When the branch holds the unqueue's commit (`wip_commit`), the comment names it and says it must be rewritten to one of the project's commit types before a merge by hand; with none, it says nothing of it.

Done when you have shown the person each draft with its path, and each has gone out on their word or stays as a file they know of:

- one comment for the bound issue: the first cause, the road and what came of it, where the salvage is (`kind: "issue-comment"`)
- for an advance or the door, the pull request section saying the work came out of a repair (`kind: "pull-request"`)
- one finding per pipeline or task-document defect (`kind: "finding"`, listed in `defects`). It goes to the findings channel: a comment on the project's weekly digest issue, which a person opens. Ask the person which issue is this week's digest, and for the class and the type each draft leaves open; in a week with no digest open the draft stays a file, and you tell them where.
