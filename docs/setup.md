# The setup skill

> **Planned, not yet shipped.** This page describes the design of `spoolway-companion:setup`. Until
> it ships, a consumer does the same by hand from [extension-points.md](extension-points.md),
> [multi-repo.md](multi-repo.md) and [issue-tracking.md](issue-tracking.md).

The setup skill writes the consumer side of every extension point into a repository, and moves an
installed consumer to a newer pin. One skill does both: there is one entry point whether the
repository is new to the companion or already on it.

## What it detects

It reads what is there file by file and key by key; it keeps no marker of its own. A file that
exists is the consumer's: the skill only adds the keys and entries it lacks and never changes a
value already set. The one value it changes is the companion's own pinned `sha`, on a version
bump. It never writes a path `plugin.lock` lists; those go through `types.sh write`.

A repository still on an older plugin is detected and left alone: moving it over is the work of
its own cut-over, not of setup.

## The interview

It asks, in order, one topic at a time, proposing an answer from what it found:

1. **Topology**: which repositories the project spans, and what `repos` means in its tasks
   ([multi-repo.md](multi-repo.md)).
2. **Pipelines**: which ones the repository runs, written to `.spoolway/types.subset`.
3. **Issue tracking**: whether to copy the `github.sh` hook and the workflow, which labels to
   create, and the `[issue_tracking]` keys ([issue-tracking.md](issue-tracking.md)). It checks that
   the repository has `docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md`, and offers
   the skill that writes them when it does not.
4. **Destinations**: `RUN_REPORT_REPO`, `FINDINGS_REPO`, and the repository Materializing opens
   tickets in. A private destination stays out of the tracked file, in the dispatcher machine's
   environment.
5. **Pages**: the `PAGES_*` keys, and whether to install a page write path such as llm-wiki.
6. **Scripts**: `checks.sh`, `handover.sh`, the `extra-*` scripts and the `materializing-*`
   scripts, each written as a starting point for the consumer to finish.

Then it shows a summary of every file and key it will write, and writes nothing until the user
confirms. It creates only the labels that are missing, and leaves its files uncommitted on a
branch for the user to review.

## A version bump

On a repository already on the companion, it moves the pinned `sha`, installs or updates the plugin
for each project path, takes the types and the lock again with `types.sh write`, writes any file and
key the new version adds, and prints a diff for each copied template the new version changed,
which it does not apply ([issue-tracking.md](issue-tracking.md#keeping-the-templates-current)).

The pin is always an inline, sha-pinned `spoolway-companion` entry in the consumer's
`.claude/settings.json`.
