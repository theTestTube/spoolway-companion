# Issue tracking

The pipelines run without an issue tracker. What the companion adds for GitHub issues is one
spoolway hook and one workflow, both templates a consumer copies once and then owns: the companion
never updates either, and a pin bump never touches them.

- `templates/github.sh` → `.spoolway/hooks/github.sh`
- `templates/spoolway-issues.yml` → `.github/workflows/spoolway-issues.yml`

Turn the hook on in `.spoolway/config.toml`:

```toml
[issue_tracking]
hook = "github.sh"
project_key = "owner/repo"   # the repository where pull requests open
```

A blank `hook` means no hook. The hook needs `gh` signed in on the machine that runs the
dispatcher.

## What the hook does

A task is bound to the issue it was queued against: its `ticket:`, a full issue URL when the issue
lives in another repository than the pull request. spoolway calls the hook on each event:

- **`open`**, for a document queued with no `ticket:`: binds it to the issue its `source:` names,
  and refuses a document with no issue behind it. A task of the `feeding-back-weekly` group binds
  to the one open "Weekly digest" issue instead.
- **`fetch`**: answers `spoolway issue show` with the issue's title, state, labels, body and
  comments.
- **`queued`**: labels the issue `spoolway:in-progress`.
- **`blocked`** and **`paused`**: a comment with the task's latest Status Log and Handoff, so the
  issue shows where the task stopped and why.
- **`done`**: finds the task's pull request, leaves a marker comment on it naming the issue, swaps
  `spoolway:in-progress` for `spoolway:review`, adds `spoolway:task` when the issue should close on
  merge, and comments that the task is ready for review.

It writes those three labels and no other; triage labels are read, never written. It never opens
an issue.

The workflow runs when a pull request merges. It finds the marker, and closes the issue only if it
carries `spoolway:task`, stripping the queue-state labels. The label is withheld, so the issue
stays open after the merge, when the task says `close_on_merge: false` (a spec that several tasks
build), when the issue carries `wayfinder:map` or `ready-for-human`, or when the issue lives in
another repository than the pull request.

## Without the hook

A consumer that leaves `hook` blank, or tracks its work somewhere other than GitHub issues, loses:

- **The `spoolway:*` labels**: no `spoolway:in-progress` or `spoolway:review` on an issue; the
  board is the only place a task's state shows.
- **Close on merge**: merging a task's pull request closes nothing. Close the issue by hand, or
  with a closing keyword in the pull request, which the companion's own `handover.sh` refuses, so
  a consumer that wants keywords writes its `handover.sh` to allow them.
- **Issue reads through spoolway**: `spoolway issue show` has nothing to answer with.
- **Status comments**: a blocked or paused task leaves no comment on its issue.
- **Binding on queue**: a document without `ticket:` is not refused for lacking an issue, and the
  weekly Feeding-back task is not bound to the digest issue.

The pipelines still run, every step of them. Nothing in a pipeline file names the hook, and no step
script calls it. The lanes that read an issue (`ticket:` in a resolve or a Materializing task, the
digest in Feeding-back) read it with `gh` themselves, so a consumer on GitHub without the hook
keeps those. A consumer whose issues are elsewhere writes `ticket:` as whatever its own scripts and
prompts can follow.

## Labels

The hook and the workflow assume the three `spoolway:*` labels exist in the repository that holds
the issues, and the Architecting and Materializing pipelines read `wayfinder:*` and triage labels.
Create them once; the setup skill ([setup.md](setup.md)) is planned to create only the missing
ones.

## Keeping the templates current

Because the copies are the consumer's, a newer template does not reach them. When the companion
changes a template, its release notes say so; compare with `diff templates/github.sh
.spoolway/hooks/github.sh` from a checkout of the companion at the new pin and take what you want.
