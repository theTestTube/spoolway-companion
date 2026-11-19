# The setup skill

`/spoolway-companion:setup` is started by a person in the consumer's checkout. Its mechanical half
is `claude-plugin/skills/setup/setup.sh` (`detect`, `plan`, `apply`, `labels`, `bump`, `memex`), tested by
`tests/spoolway-setup.test.sh`. A consumer can still do the same by hand from
[extension-points.md](extension-points.md), [multi-repo.md](multi-repo.md) and
[issue-tracking.md](issue-tracking.md).

The setup skill writes the consumer side of every extension point into a repository, moves an
installed consumer to a newer pin, and reviews the move of spoolway itself to another release. One
skill does all three: there is one entry point whether the repository is new to the companion,
already on it, or about to change its spoolway binary.

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
6. **Scripts**: `checks.sh` (with the commands the user's CI runs), `handover.sh` and the
   `extra-*` scripts, each written from a template as a starting point for the consumer to finish.
   The `extra-*` templates serve both topologies: for a multi-repo, setup also writes the
   `extra_repos` and `worktree_root` answers into `.spoolway/companion.env` as `EXTRA_REPOS` and
   `EXTRA_WORKTREE_ROOT`, which they read ([multi-repo.md](multi-repo.md#the-companions-templates)).
   With Materializing taken, setup also writes its five `materializing-*` scripts.

7. **Memex upkeep**: whether and when `memex index` runs to keep the memory index's vectors
   current (`none`, `hourly`, or `boot`, one pass 3 minutes after the user session starts), and
   the value of `auto_index_on_search`. See [Memex upkeep](#memex-upkeep).

Then it shows a summary of every file and key it will write, and writes nothing until the user
confirms. It creates only the labels that are missing, and leaves its files uncommitted on a
branch for the user to review.

## Memex upkeep

Unlike everything above, this part is the machine's, not the checkout's: `setup.sh memex plan` and
`setup.sh memex apply` write memex's `~/.memex/config.toml` and the user's systemd timer, and none
of it shows in `git status` or the pull request. The same rule holds: it adds what is missing,
reports a differing value and keeps it, and it never removes a timer. Answers are the lower-case
keys `memex_schedule` and `memex_auto_index_on_search`.

- **Schedule.** `hourly` and `boot` install the timer through `memex daemon enable --interval 3600`
  and a resource-limits drop-in; `boot` adds a timer drop-in that replaces the hourly trigger with
  `OnStartupSec=3min`. Installing the timer starts it, so one pass runs right away. Each pass loads
  the embedding model (about 3 GB of RAM for under a minute with the default model), which is why
  `boot` is the recommended answer on a memory-tight machine. A timer runs plain `memex index`, so
  setup also turns `embeddings` on. An index with fewer than 1000 vectors gets no timer: its first
  pass is a full backfill that the limits would throttle, so setup asks for it by hand first.
- **`auto_index_on_search`.** With `true`, every search re-scans the history and indexes what is
  new; with `false` a search only reads. The default follows the schedule: `false` when a timer
  exists, because the timer is then the one writer (memex's own `daemon enable` adds the same
  value, with the note "Background indexing handles freshness; avoid duplicate scan work during
  search"), and `true` when nothing is scheduled, because nothing else would refresh the index. The
  cost of `false` with `boot` is that a search can miss the current session's work until the next
  login or a manual `memex index`.

## A version bump

On a repository already on the companion, it moves the pinned `sha`, installs or updates the plugin
for each project path, takes the types and the lock again with `types.sh write`, writes any file and
key the new version adds, and prints a diff for each copied template the new version changed,
which it does not apply ([issue-tracking.md](issue-tracking.md#keeping-the-templates-current)).

The pin is always an inline, sha-pinned `spoolway-companion` entry in the consumer's
`.claude/settings.json`.

## A spoolway update

Started as `/spoolway-companion:setup spoolway` (the latest release) or `/spoolway-companion:setup
<version>`. It writes nothing outside `./.scratch/`; the checkout's files, the binary, the
dispatcher and the queue stay as they are until the person acts.

1. **Review the gap.** The installed release (the As-Is) against the target (the To-Be), forward or
   back, with the notes of every release between them and `docs/migrations.md` read at the tag, never
   at the default branch. Going back, it is read at the installed tag as well, since only that tag
   documents what the undone release changed.
2. **Probe.** On the person's word it downloads the To-Be binary into `./.scratch/`, checks its
   hash and installs nothing. It runs `sync --dry-run`, `pipeline check`, `doctor --no-live` and the
   checkout's own gates and tests under both binaries, and separates new failures from pre-existing
   ones.
3. **Map.** Each breaking change of the gap is matched to the checkout's files and reported as a
   hit or no hit with its evidence, classed **before** (the fix also works under the installed
   binary) or **after** (it needs the new one). Queued tasks, machine-local files `sync` would write
   and active overrides are accounted for.
4. **Propose runs.** When the gap is not empty it drafts Developing, Materializing, Architecting or
   Feeding-back runs from the checkout's own task templates, checks them with `task contract --from`,
   and queues or opens nothing without the person's word. The rule that picks the run is in
   `update-runs.md` beside the skill.
5. **Hand over.** Installing the binary, restarting the dispatcher, taking the `sync` and
   `dispatch reload` are the person's and are named as `to do:` lines in order.

A rollback is a flight forward: running processes and tracked files already hold what the newer
binary wrote. The skill lists every task queued or started under the installed release with what
its unqueue destroys, salvages the work first, proposes the unqueue, and goes no further unless the
person writes an opt-in that names the target release (`update-rollback.md`). What earlier gaps
hit, each with the command that shows whether it holds again, is in `update-gotchas.md`.
