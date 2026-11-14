# Multi-repo pipelines

Some changes span repositories: an app and the library it builds against, a service and its
infrastructure. spoolway runs a task in one worktree of one repository; the companion adds what a
task needs to change others alongside it, without knowing which ones or how they are related.

The pieces are three steps of the Developing pipeline, one frontmatter key, and the consumer's
scripts behind the steps ([extension-points.md](extension-points.md)).

## The pieces

- **`repos`**: a frontmatter list on the task naming the repositories it changes. The companion
  never interprets it: it passes it through to the consumer's scripts and to the prompts, and the
  consumer decides what an entry means (a repository name, a directory, a short alias). A task
  with no `repos`, or one naming only its own repository, is a single-repo task.
- **`extra-worktree`** (first step): the consumer's `scripts/spoolway/extra-worktree.sh` cuts a
  worktree on the task's branch name in each extra repository `repos` names. It fails, and the
  task blocks, when a repository cannot be reached or a worktree cannot be cut.
- **`extra-handover`** (after `review`, before `handover`): the consumer's script pushes each extra
  repository's branch and opens its pull request, then waits for whatever must be green before the
  task's own pull request opens. It runs first because a consumer's CI often resolves the sibling
  repositories by the branch name: the extra branches have to exist on the remote before the main
  pull request's CI starts. The step's `timeout` is the `ci` step's, 45 minutes, sized for one
  wait of `CI_WAIT_SECONDS`; a script that waits on several extra repositories one after another
  raises it on its own machine with
  `spoolway pipeline override developing --set extra-handover.timeout=<n>m` (spoolway 0.17.0 or
  later), and the same for every other Developing pipeline it runs.
- **`extra-cleanup`** (after `report`, before `collect`): the consumer's script removes the extra
  worktrees. It leaves alone a worktree holding work the remote does not have, says so, and still
  passes, so nothing unpushed is lost and the task still finishes.

Every one of the three passes at once for a task whose `repos` names no extra repository. That
check is the consumer's: the companion has no list of repositories to compare against.

## What the shipped steps assume

- The `ci` step (`ci.sh`) waits only on the task's own pull request in the run's repository. The
  extra pull requests and their CI belong to `extra-handover`.
- A task that changed only extra repositories leaves its own branch with nothing to merge.
  `task_unchanged` in `lib.sh` tests for exactly that: the consumer's `handover.sh` uses it to open
  no pull request and pass, and `ci` uses it to pass with no pull request to wait on.
- The implementing and reviewing lanes edit an extra repository only in its worktree. They read
  where those worktrees are from the consumer's `CLAUDE.md` or `docs/agents/projects.md`
  ([extension-points.md](extension-points.md#docsagentsprojectsmd)).
- Materializing's `tickets` lane writes `repos` on each draft from the grill's breakdown, and the
  consumer's `materializing-drafts.sh` may check the two agree.

## A worked example

`acme/shop` is a web shop; its UI components come from `acme/shop-lib`, a library checked out
beside it and built from source in CI. Tasks are queued in `acme/shop`. A task that changes a
component and the page using it carries:

```yaml
---
id: t42-checkout-button
title: "feat(checkout): show the total on the pay button"
group: checkout
pipeline: developing
ticket: https://github.com/acme/shop/issues/42
base: main
repos: [shop, shop-lib]
---
```

`acme/shop` keeps where the library's worktrees go as a key of its own:

```text
# .spoolway/companion.env
SHOP_LIB_WORKTREES=../shop-lib-worktrees
```

and its `scripts/spoolway/extra-worktree.sh` reads it:

```bash
#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

no_arguments extra-worktree "$@"
own_step extra-worktree
step_skipped "$SPOOLWAY_TASK_FILE" extra-worktree && exit 0
frontmatter_list_has "$SPOOLWAY_TASK_FILE" repos shop-lib || { echo "extra-worktree: no extra repository"; exit 0; }

root=$(companion_env SHOP_LIB_WORKTREES)
[ -n "$root" ] || { echo "ENVIRONMENT: SHOP_LIB_WORKTREES is not set in .spoolway/companion.env" >&2; exit 1; }
[ -d ../shop-lib ] || { echo "ENVIRONMENT: no shop-lib checkout beside this repository" >&2; exit 1; }

branch=$(git branch --show-current)
git -C ../shop-lib fetch origin
git -C ../shop-lib worktree add -B "$branch" "$root/$branch" origin/main
```

The run then goes:

1. `extra-worktree` cuts `../shop-lib-worktrees/<branch>` on the task's branch name.
2. `implement` changes the component there and the page in the task's worktree, as `CLAUDE.md`
   tells it where the library's worktree is. `checks` runs `acme/shop`'s checks, which build the
   library from the sibling worktree.
3. `review` reads both diffs.
4. `extra-handover` pushes the library branch, opens its pull request in `acme/shop-lib`, and waits
   for its CI.
5. `handover` opens the `acme/shop` pull request. Its CI checks out `acme/shop-lib` at the branch of
   the same name, which now exists. `ci` waits on this pull request only.
6. After `report`, `extra-cleanup` removes the library worktree once its branch is on the remote.

Who merges the two pull requests, and in what order, is the consumer's process: the library first,
here, so the shop's `main` never builds against a library change that is not merged. A task that
waits on another project's work names it in `requires:`, which `handover.sh` renders as a
`## Waits on` section of the pull request body.

## A consumer with one repository

It still owns the three scripts, because the steps are in the pipeline. The companion's own
`scripts/spoolway/extra-*.sh` are the shape: each passes at once, and blocks only when a task's
`repos` names more than one repository, so a task meant for another project is not silently built
in this one.
