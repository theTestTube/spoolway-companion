---
id: smoke-implement-spec
title: 'feat(smoke): build one small spec with implement-spec'
stage: blocked
blocked_from: implement
last_report:
  step: implement
  outcome: block
  at: 1791363227
pipeline: developing
group: smoke-implement-spec
group_description: Smoke run of the implement-spec alternative implementer (#321)
source: https://github.com/example/app/issues/217
branch: task/smoke-implement-spec
base: develop
run: r9d3a03d205b6e937
cut_from: develop
base_commit: @BASE_COMMIT@
worktree_path: @WORKTREE@
workspace_id: w30
pane_id: w30:p1
tab_id: w30:t1
steps:
  blocked->implement: 2
  blocked->implement-spec: 1
  checks->review: 2
  implement->implement-spec: 2
  implement-spec->checks: 2
  queued->extra-worktree: 1
  review->implement: 2
  extra-worktree->implement: 1
rounds:
  blocked->implement: 2
  blocked->implement-spec: 1
  checks->review: 2
  implement->blocked: 3
  implement->implement-spec: 2
  implement-spec->blocked: 1
  implement-spec->checks: 2
  queued->extra-worktree: 1
  review->implement: 2
  extra-worktree->implement: 1
arrivals:
  blocked: 4
  checks: 2
  implement: 5
  implement-spec: 3
  review: 2
  extra-worktree: 1
arrived_from: implement
close_on_merge: false
implementer: implement-spec
issues:
- https://github.com/example/app/issues/217
repos:
- app
skip_steps:
- implement
ticket: https://github.com/example/app/issues/217
---

## Context

- The input issue is a spec; its tickets are the issues it lists or that name it as parent, with `Blocked by` giving the graph.
- #321 added the `implement-spec` step beside `implement`; this run is its smoke run.
- The lane's own worktree is the integration branch; at most 2 implementer subagents run at once, each in a worktree beside this one, removed when merged.

## Intend

Build every open ticket of the spec on this task's branch and hand over one pull request that says `Part of` the spec.

## Non-goals

- Closing, labelling or commenting on the spec or its tickets.
- Any device, deploy, secret or store step.
- anything not required by the acceptance criteria below

## Acceptance criteria

- [ ] Every open ticket of the spec is built and committed on this task's branch.
- [ ] No more than 2 implementer worktrees existed at any moment, and none remains at the end (`git worktree list`).
- [ ] `checks` and `review` pass, and `handover` opens one pull request with no closing keyword.

## References

- the input issue, named by `ticket:` in the frontmatter, read live
- docs/spoolway-developing.md, "Choosing the implementer"

## Left for a person

- [ ] Device QA on a development build, when the change reaches the UI or native code
- [ ] Deploys of any stage, when the change needs one
- [ ] Secrets and credentials, when the change needs one set or rotated
- [ ] Store steps: release build, submit, store track

## Status Log
- 2026-10-06 19:57 → `extra-worktree`
- 2026-10-06 19:57 → `implement`
- 2026-10-06 19:57 `implement`: no readable earlier `developing-implement` session on this task — opened fresh
- 2026-10-06 19:57 → `checks`: skip_steps names implement; nothing changed
- 2026-10-06 20:01 → `review`
- 2026-10-06 20:03 → `blocked`: review: nothing to review, the diff develop...HEAD is empty; the pipeline in use has no implement-spec step, so no ticket of the spec was built
- 2026-10-06 20:22 → `extra-worktree`
- 2026-10-06 20:23 → `implement`
- 2026-10-06 20:23 → `implement-spec`: skip_steps names implement; nothing changed
- 2026-10-06 20:23 `implement-spec`: no readable earlier `developing-implement-spec` session on this task — opened fresh
- 2026-10-06 20:40 → `blocked`: #229 and #231 built on the branch; #230 not buildable: 58 files remain in legacy-notes/, ~27 have no manifest row and no page, and removing them needs a triage and issues for live knowledge, which this lane may not open
- 2026-10-07 01:33 → `implement-spec`: unblocked by hand
- 2026-10-07 01:34 → `checks`: #229 and #231 built on the branch; #230 left unbuilt on purpose (the person cleared the block with no triage or issues, so its blocker stands)
- 2026-10-07 01:34 → `review`
- 2026-10-07 01:56 → `implement`: 11 findings on #229 and #231, one handoff note each: the doc-audit script fails open on a GitHub error and its first-run anchor is unreachable from origin/develop; two Widget pages state things the code contradicts and one compiles an open question; three commit subjects are off the type list; #230 is not built. Part of #217, leaves #229, #230 and #231 open
- 2026-10-07 01:57 → `implement-spec`: skip_steps names implement; nothing changed, review findings go to implement-spec
- 2026-10-07 02:05 → `checks`: review findings 1-10 fixed on #229 and #231 (merge commits removed, history linear); #230 still unbuilt
- 2026-10-07 02:05 → `review`
- 2026-10-07 02:29 → `implement`: 6 small findings on #229 and #231, one handoff note each: the cycle-bar anchor in page-widget-view.md:53 names the wrong lines; drift rows 83, 86 and 87 of page-widget-states.md carry no library anchor and its summary at :19 contradicts itself; pages/index.md:40 misstates which manifest the Widget pages anchor on; step 1 of the routine prompt has no rule for a failed anchor; doc-audit.md:17 records decisions in a tracked doc; #230 is not built, for a person. The ten earlier findings hold as repaired. Part of #217, leaves #229, #230 and #231 open
- 2026-10-07 02:30 `implement` may not send this to `implement-spec` a 4th time — `implement-spec` has `loop: 3`; carrying on to `blocked`
- 2026-10-07 02:30 → `blocked`: skip_steps names implement; nothing changed, review findings go to implement-spec
- 2026-10-07 07:42 → `implement`: unblocked by hand
- 2026-10-07 07:42 `implement` may not send this to `implement-spec` a 4th time — `implement-spec` has `loop: 3`; carrying on to `blocked`
- 2026-10-07 07:42 → `blocked`: skip_steps names implement; nothing changed
- 2026-10-07 07:43 → `implement`: unblocked by hand
- 2026-10-07 07:43 `implement` may not send this to `implement-spec` a 4th time — `implement-spec` has `loop: 3`; carrying on to `blocked`
- 2026-10-07 07:43 → `blocked`: skip_steps names implement; nothing changed

## Handoff
- `review` — Finding (acceptance, criterion 1): the task's branch has no commit; develop, HEAD and base_commit are all 75cb41c and 'git diff develop...HEAD' prints nothing. Spec #217 is OPEN with three open tickets, #229, #230 and #231, and none of them is built. This run is part of #217 and leaves #229, #230 and #231 open. The two review subagents were not started: the code-review skill stops on an empty diff.
- `review` — Cause, outside the diff: the developing pipeline bound at the main checkout (/work/app, develop at 75cb41c) predates PR !389 and has no implement-spec step, and its developing-implement prompt passes at once when skip_steps names implement. The task therefore went extra-worktree, implement (nothing changed), checks, review, and no step built anything. origin/develop is at ec22bb0, the merge of PR !389, which adds the step.
- `review` — For a person: bring the main checkout's develop up to origin/develop (ec22bb0) so the bound pipeline carries implement-spec, after looking for a machine config override that a sync would overwrite. This task's branch was cut at 75cb41c, before that merge, so it has to be cut again or moved onto the updated develop before the smoke run is repeated.
- `review` — Why a block and not a fail: review fails back to implement, which skip_steps makes pass with nothing changed, so a failing verdict would only repeat checks and review until the loop on implement is spent. No implementer could act on the finding.
- `review` — Criterion 2, as far as it can be seen: 'git worktree list' shows no implementer worktree beside task-smoke-implement-spec, but none was ever cut, so the two-at-once limit was not exercised. Criterion 3 is unmet: no review verdict on a change, and no pull request.
- `implement` — implement was skipped again by skip_steps, so the branch still has no commit and the diff is empty. Remove implement from skip_steps (or run the pipeline with implement-spec) before expecting any ticket of #217 to be built; this run is part of #217 and leaves #229, #230 and #231 open.
- `implement-spec` — Built (part of #217): #229 Widgets area (two decision pages, self-manifest app-2026-10-06.md, 8 records retired in one commit; runner GREEN 546/0 red, lint 0, typecheck and tests green at ed257d0) and #231 drafted (scripts/doc-audit.sh + offline test, docs/agents/doc-audit.md; 21 ok). Leaves #229, #230 and #231 open.
- `implement-spec` — needs a person: #229 — open the class-4 issue 'Widgets: decide the rule that assigns items to transitional states 4 and 8' (draft in @STATE@/scratch/smoke-implement-spec/t229-notes.md) and link it from the triage table before merge; post the triage table, runner output and domain review from that notes file on #229; optionally a library issue: labels.ts:7 marks a dataset 'Public Domain' though its licence says otherwise (contradicts page-data-licences).
- `implement-spec` — needs a person: #231 — create the routine by hand with the schedule skill using the prompt in docs/agents/doc-audit.md (cron 0 7 1 * *), list it, then the two dry runs (AC2/AC3) in the order the doc gives. Doc sits in docs/ so the size baseline is untouched.
- `implement-spec` — #230 blocker: legacy-notes/ still holds 58 files after #229; 27 have no manifest row and no page (README, two integration notes, ~12 decisions and ~12 reasoning logs). the project rules forbid silently deleting live knowledge: each needs triage, a compile or an issue first. Not attempted; needs a person to run the triage or open the issues, then #230 can be built.
- `implement-spec` — worktrees: at most 2 implementer worktrees existed (t229, t231); both merged and removed, git worktree list shows no -t* entry.
- `implement-spec` — #230 NOT built, part of #217 and left open: 58 files remain in legacy-notes/ (27 with no manifest row and no page); the project rules forbid silently deleting live knowledge and no triage or issues exist yet. Review the diff as #229 + #231 only; acceptance criterion 1 of the task is met for those two, not #230.
- `implement-spec` — needs a person: the class-4 issue for #229 (draft in @STATE@/scratch/smoke-implement-spec/t229-notes.md) must be opened and linked before the branch merges; triage table, runner output and domain review are in that notes file for #229.
- `implement-spec` — needs a person: #231 routine creation by hand (schedule skill, prompt in docs/agents/doc-audit.md, cron 0 7 1 * *) and the two dry runs; no -t* worktree remains.
- `review` — Finding 1 (spec #231, "skips when no target changed since the last audit"; the script's own header lines 13-15; docs/agents/doc-audit.md:29-30 and :91) — scripts/doc-audit.sh:42-44 and :161-170: `anchor` fails open. When `gh api` errors, `rows` yields nothing, `anchor` prints "no earlier audit issue" and exits 0 on the baseline anchor. Reproduced with a `gh` that exits 1: exit 0, plus an integer-expected error from line 44. A flaky proxy would make the routine audit again from the baseline and open a duplicate issue. A failed GitHub read has to exit 1, with an offline test case that shows it.
- `review` — Finding 2 (the script's header: "An anchor missing from a shallow clone is an error, never a skip") — scripts/doc-audit.sh:189 with :33-35: `open <anchor missing from the clone>` exits 3, a skip, where `draft` with the same anchor exits 1. Both reproduced. `|| exit $?` turns errexit off inside `draft`, `commit_of` ends only its own subshell, and `|| true` on line 35 swallows git's "bad revision". scripts/doc-audit.test.sh:56-58 covers the missing anchor for `changed` only.
- `review` — Finding 3 (spec #231 criterion 3, the first run the doc prescribes) — scripts/doc-audit.sh:166 and docs/agents/doc-audit.md:27-28, :50-52: the first-audit anchor is `measured_at` in the baseline, b69cdc123c5d, which is reachable from no ref and is not an ancestor of origin/develop (`git merge-base --is-ancestor` exit 1, `git for-each-ref --contains` empty). A routine's fresh clone will not hold it, so `anchor` dies at step 1 and "deepen it" cannot help. My own `changed`/`draft` dry run on the real repo passed only because this machine's object store still holds that commit. The fallback has to be a commit reachable from origin/develop, and the doc should not call it "the commit the baseline measured": the baseline file has 16 commits on develop. Leave scripts/gates/size-baseline.json untouched.
- `review` — Finding 4 (spec #231, "baseline deltas") — scripts/doc-audit.sh:92-104: the table is headed "Size against the baseline" but its delta column is tip minus anchor; the baseline is only a column and no delta against it is printed. scripts/doc-audit.test.sh:127 pins that shape (baseline 40, tip 43, delta ±0). Small.
- `review` — Finding 5 (spec #229, domain review applied to every page; schema drift rule: the code wins) — pages/page-widget-states.md:56-57: the sentence says the legacy scheme's states "imply other colours:" and then lists the pairs A and B red, C and D green, E and F blue, which are the colours the widget ships (lib@19a6272:packages/widgets/src/data.ts lines 75, 89, 103, 131, 145, 159). The domain-review edit was spliced so the meaning is inverted.
- `review` — Finding 6 (spec #217, "drift found while compiling is recorded on the page, anchored") — pages/page-widget-view.md:44: "Unlike Clock, the arrows are never disabled" is false. ClockView passes the same unconditional neighbours and handlers (lib@19a6272:packages/clock/src/ClockView.tsx:303-307), and WidgetView disables an arrow whenever its handler is null (packages/widgets/src/WidgetView.tsx:138-139, :156-157). The :24 anchor supports the wrap-around only.
- `review` — Finding 7 (same rule, the page contradicts itself) — pages/page-widget-view.md:40: "That swap is the only visual signal that a state is transitional", while :47 (the cycle bar falls back to the abstract group colour) and :50 (the element badge and group row are left out) name two more on the same page.
- `review` — Finding 8 (pages/schema.md:302-306, "Open items become issues, not pages ... Record where each one went"; spec #229 criterion 2) — pages/page-widget-states.md:65-87 compiles the transitional-states question into the page as a full `## Open question` analysis. Line 83 ("The issue names both") describes an issue that does not exist, and :85-87 ("before this page reaches develop") goes stale at merge. Cut the section to a short pointer that the question went to an issue and keep the analysis in the issue draft (t229-notes.md:61). Putting the issue number in is the person's step, below.
- `review` — Finding 9 (CLAUDE.md, Commit Message Format: types feat fix docs refactor perf test build ci chore) — commits bd1e149 and 34cb212 use the type `merge:`, and 2bdd7e5 carries git's default "Merge branch ..." subject. The branch is not pushed, so the three can be reworded; ed257d0 keeps its SHA through that, so the same-commit evidence in t229-notes.md stays true.
- `review` — Finding 10 (accuracy of the deliverable doc) — docs/agents/doc-audit.md:31-32 says the audit measures origin/develop "because the repo default branch is not where the targets change". The default branch is develop (`gh api repos/example/app --jq .default_branch`). Give the real reason (objects, never the working tree) or drop the clause. Small.
- `review` — Finding 11 (task acceptance criterion 1) — #230 is OPEN and not built: legacy-notes/ still holds 59 files at HEAD (28 with no row in any self-manifest, README and two .gitkeep among them; 31 named in an earlier self-manifest yet still in the tree, not looked into; 7 logs `in_progress`). This is part of #217 and leaves #230 open. Not the implementer's to build or attempt on this lap: it needs a triage reviewed on the ticket and issues only a person may open. If it is the only finding left on the next lap, review blocks for a person.
- `review` — For a person: the branch must not merge before the class-4 issue exists. Open "Widgets: decide the rule that assigns items to transitional states 4 and 8" from the draft at t229-notes.md:61, then put its number in the page pointer (finding 8), in page-widget-states.md:118, in pages/index.md:48-49 and in the triage table. The self-manifest row (app-2026-10-06.md:40) already points at the triage table and is write-once: leave it.
- `review` — For a person: the #229 triage table (t229-notes.md:36), the domain review (:95) and the runner output (:313) exist only in @STATE@/scratch/smoke-implement-spec, which is deleted with the task. Post them on #229 before the task ends.
- `review` — For a person: create the #231 routine only after finding 3 lands, or its first run dies at the anchor. If #230 was meant to stay out of this run, say so by amending acceptance criterion 1; review cannot waive it.
- `review` — For a person, a judgment for the #229 triage (not a finding): the self-manifest classes the design log "7 Not a decision", yet page-widget-view is an accepted decision page whose only History row is that log ("Decisions 1-7"). The schema allows a page reconstructed from code; decide whether this is a live lineage or a page per log.
- `review` — Verified at HEAD bd1e149 (what holds): scripts/gates/run.sh self-manifest same-commit unanchored-refs stale-pages size = 403 green, 0 red; lint gate 0 critical, 0 warnings, 0 freshness; all 8 manifest blob SHAs match and equal the 8 deletions; every library citation is a manifest row and 9 line anchors were read against 19a6272; scripts/doc-audit.test.sh 21 ok under C and es_ES; no AI attribution, secret, baseline edit, device or deploy step, or closing keyword in the diff or the commit messages. The tree stayed clean.
- `review` — Acceptance criterion 2: no `-t229` or `-t231` worktree or branch remains (`git worktree list`, `git branch --list`). That at most 2 existed at once rests on the implementer's word: UNVERIFIED. Criterion 3 is not met yet: this review does not pass. The two review subagents ran; no other was started.
- `implement-spec` — Fixed from review: findings 1-4 and 10 (doc-audit fails closed, missing anchor errors, first-audit anchor is 8d9c192 on origin/develop, tip-vs-baseline column, doc reason), 5-8 (Widget pages; open question cut to a pointer), 9 (branch rebuilt linear: no merge commits). Evidence: doc-audit.test.sh 27 ok; gates self-manifest/unanchored-refs/stale-pages/size GREEN 392; page lint 0 findings; same-commit holds on ed257d0. Part of #217; leaves #229, #230 and #231 open.
- `implement-spec` — Finding 11 not actioned by design: #230 (legacy-notes/ leaves the tree) is unbuilt, it needs a triage and issues only a person may open; if criterion 1 should exclude it, a person amends it.
- `implement-spec` — needs a person: open the #229 class-4 issue (draft in @STATE@/scratch/smoke-implement-spec/t229-notes.md, now holding the full analysis), link it from the triage table, put its number in page-widget-states.md Open question if wanted; post the triage table, domain review and runner output from that file on #229 before the task ends (scratch is deleted with the task); decide whether page-widget-view is a live lineage or a page per log.
- `implement-spec` — needs a person: create the #231 routine by hand (schedule skill, prompt in docs/agents/doc-audit.md, cron 0 7 1 * *); the first live run covers 8d9c192..tip and asks for 9 verdicts; live anchor against GitHub and the shallow-clone unshallow fetch are UNVERIFIED.
- `review` — Lap 2 verdict: fail on six small findings the implementer can act on (1 to 6 below); finding 7 is for a person. All ten actionable findings of the first lap are resolved at HEAD 5a21d01, checked by both review subagents and by hand: `anchor` exits 1 on a failed or non-array GitHub page (scripts/doc-audit.sh:47-48, :167); `draft` and `open` exit 1 on a missing anchor (:125-127); the first-audit anchor is 8d9c192, an ancestor of origin/develop (b69cdc1 is not); the packet prints the period delta and tip against baseline; the two Widget pages' reworded claims match lib@19a6272 and @8ad29f7; ten linear commits, all on the type list. Part of #217, leaves #229, #230 and #231 open.
- `review` — Finding 1 (spec #229, the library code is cited through the collection; pages/schema.md drift rule, the code wins: an anchor has to name the code its sentence describes) — pages/page-widget-view.md:53: decision 4 anchors the cycle bar's fallback colour to `lib@19a6272:packages/widgets/src/WidgetView.tsx:75`, but :75-81 computes `stateColor` for the state on screen. The cycle bar's per-segment fallback to `abstractColors.group` is WidgetView.tsx:187-196 (the bar starts at :181). Point the anchor there. page-widget-states.md:50 cites :75 for the view's state colour and is right as it stands.
- `review` — Finding 2 (spec #217, "Drift found while compiling is recorded on the page, anchored (#186 item 8)") — pages/page-widget-states.md:83, :86 and :87: three drift rows name code with no `lib@19a6272:<path>` anchor. The code is `widgetDayRange` at packages/widgets/src/data.ts:32 (values from :78), `StateInfo` at data.ts:12-32, and `produces` at packages/widgets/src/index.ts:34 against the three `emitOutput` calls at WidgetView.tsx:84, :92 and :100. Row :85 rests on the `binary` strings and has no inline anchor either; its file, `lib@8ad29f7:packages/items/src/items.ts`, is named only in Provenance. Commit aeeb970's subject says every library citation is anchored.
- `review` — Finding 3 (accuracy of the pages' manifest table; pages/schema.md:99-101, a superseded manifest stays as the pin of the pages still anchored to it) — pages/index.md:40 says the 2026-09-13 library manifest is the code anchor of the Widget pages, "whose paths are its rows only". That is false: `packages/widgets/src/WidgetView.tsx` and `WidgetHeader.tsx` are also rows of pages/raw/lib-2026-09-28.md (:60-61, same blobs), and both pages cite rows only that manifest has (`packages/clock/src/ClockView.tsx` :48, `packages/items/src/items.ts` :43). Line :39, the 2026-09-28 row, lists its pages without the Widget pages. Reword :40 and name the Widget pages on :39. Both reviewers raised it; the first lap missed it.
- `review` — Finding 4 (a page may not contradict itself, the rule of the first lap's finding 7) — pages/page-widget-states.md:19: the summary says the eight states are "each paired with a primary item ... and a colour", and its next sentence says the two transitional states carry no colour. Six states carry one (decision 3 and decision 5 on the same page). The summary is also the row at pages/_index.md:42, which lint regenerates from it.
- `review` — Finding 5 (spec #231, "skips when no target changed since the last audit"; docs/agents/doc-audit.md:34-35, "Only positive evidence skips") — docs/agents/doc-audit.md:100-107: step 1 of the routine prompt gives no rule for `anchor` exiting non-zero, while step 0 (:98) and step 2 (:118) each have one. The script now fails closed there, but the prompt leaves the routine to decide by itself what to do with no anchor. Add the rule: any non-zero exit, open nothing, report the error, never choose an anchor.
- `review` — Finding 6 (CLAUDE.md, Pages: "A decision is recorded one way only", on a GitHub issue or PR, then exported and compiled into a decision page; docs/agents/domain.md:39-41, "A decision has exactly one write path, and it starts on the tracker") — docs/agents/doc-audit.md:17-47: the section "Decisions taken while drafting" records nine design choices with their reasons in a tracked doc, a second authority of the kind spec #217 sets out to remove. The sibling doc keeps the split: docs/agents/permission-check.md:7 leaves the decision on its issue and calls the file "the *how*". Retitle the section and state each item as what the script does, and leave the choices to be taken on the pull request; a decision page, if one is wanted, goes through the export route and is a person's step. The standards reviewer raised it; the first lap missed it.
- `review` — Finding 7 (task acceptance criterion 1), for a person and not the implementer — #230 is OPEN and not built: `git ls-tree -r HEAD -- legacy-notes` lists 59 files. It needs a triage reviewed on the ticket and issues only a person may open, so it is not to be built or attempted on the next lap. If it is the only finding left then, review blocks for a person. A person who wants #230 out of this run amends acceptance criterion 1; review cannot waive it. Part of #217, leaves #230 open.
- `review` — Judged and not findings, so leave them: page-widget-states.md:85's clause on 11 and 23 is drift on the records' arithmetic (decision 6), not the open question; `anchor` accepts the marker anywhere in an issue body (:168-171) where the doc says the body opens with it (hardening nobody asked for); `updated:` unmoved on page-widget-sources.md (no schema rule found); the offline test's own keyword regex at scripts/doc-audit.test.sh:154 misses two verb forms (an issue body cannot shut an issue); smells in the script, all judgement calls: `TARGET` is the repo while `TARGET_PATHS` and `TARGET_RE` are the audited files, the target set is spelled three times (:22, :33, :82-88), and the same `git log` format appears at :95 and :150.
- `review` — Verified at HEAD 5a21d01 (what holds): `bash scripts/doc-audit.test.sh` 27 ok, exit 0; against the real repo `DOC_AUDIT_REF=origin/develop bash scripts/doc-audit.sh draft 8d9c192` exits 0 with 9 packets and a 15,367-character body (limit 65,000), posting nothing; its byte columns agree with scripts/gates/gates.d/size.sh (a file untouched since the last baseline edit reads ±0 against the baseline); every library line anchor on both pages was read against the library at the cited revision and all but finding 1's hold; ClockView.tsx is blob d2d46a4 at both 19a6272 and 8ad29f7 and a row of the 2026-09-28 manifest; no AI attribution, secret, edit to scripts/gates/size-baseline.json, device or deploy step, or closing keyword in the added lines or the ten commit messages; #229, #230 and #231 carry no comment, and the one comment and the `spoolway:in-progress` label on #217 are spoolway's own block notice. The gate runner and page lint were not run again by review: UNVERIFIED here, the checks step ran them green.
- `review` — For a person, unchanged from the first lap: the branch must not merge before the class-4 issue "Widgets: decide the rule that assigns items to transitional states 4 and 8" exists (draft in @STATE@/scratch/smoke-implement-spec/t229-notes.md) and is linked from the #229 triage table; #229 asks for that before the retirement lands. The triage table, the domain review and the gate-runner output exist only in that scratch file, which is deleted with the task: post them on #229 before the task ends.
- `review` — For a person: the #231 routine can be created now, the first-audit anchor resolves in a full clone and the first live run would ask for 9 verdicts over 8d9c192..develop. Better after finding 5 lands, since the prompt is pasted verbatim. The live GitHub read of `anchor` and the unshallow fetch in a routine's clone remain UNVERIFIED.
- `review` — Acceptance criterion 2: no `-t229` or `-t231` worktree or branch remains (`git worktree list`, `git branch --list`). That at most 2 existed at once rests on the implementer's word: UNVERIFIED. Criterion 3 is not met: this review does not pass. The two review subagents ran; no other was started. One of them, driving a failure path by hand, let one read-only issues-list GET through to the real `gh`; nothing was written.
- `review` — For handover, when it comes: the pull request body says `Part of #217` and "leaves #229, #230 and #231 open". Reword any status line that puts a past-tense repair verb near an issue number before reusing it.
