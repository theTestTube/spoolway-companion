# spoolway-companion

Pipeline types, hooks and skills for running coding agents through
[spoolway](https://github.com/marvingygas/spoolway): the Developing, Materializing, Architecting
and Feeding-back pipelines with their prompts, task templates and shared step scripts, a Claude Code
plugin that writes them into a repository and records the revision it took, and a repair skill for a task
that got stuck.

The companion knows nothing of any one project. A repository that consumes it fills in what is
its own behind named extension points: scripts of fixed names, a `companion.env` file and a
`docs/agents/projects.md` catalogue.

The project's vocabulary is in [GLOSSARY.md](GLOSSARY.md).

## Layout

- `claude-plugin/` is the Claude Code plugin **`spoolway-companion`**.
  - `skills/spoolway-types/` (`/spoolway-companion:spoolway-types`) writes the pipeline types into
    a consumer.
  - `skills/setup/` (`/spoolway-companion:setup`) sets a consumer up for the companion, moves it
    to a new companion revision, or reviews and drafts the move of spoolway itself to another
    release.
  - `skills/spoolway-repair/` (`/spoolway-companion:spoolway-repair <task-id>`) repairs a stuck task.
  - `skills/gh-report/` (`/spoolway-companion:gh-report owner/repo ...`) writes one HTML page of issue
    line charts (created and open, 2 weeks and 3 months) for a list of repositories, read-only.
  - `hooks/pin-drift` warns when the installed plugin is not the revision the consumer's
    `.spoolway/plugin.lock` records.
  - `spoolway/types/` is the one definition of the pipeline types.
  - `templates/` holds files a consumer copies once and owns from then on, laid out like the
    consumer with `setup/` for `.spoolway/`, `github/` for `.github/` and `claude/` for `.claude/`: the `github.sh`
    issue-tracking hook, the `spoolway-issues.yml` workflow that closes a task's issue when its
    pull request merges, the `checks`, `handover` and `extra-*` consumer scripts, and the
    `missing-plugin.sh` SessionStart hook (see Install).
    `/spoolway-companion:setup` copies them; nothing ever updates a copy.
- `tests/` holds the tests. They are outside `claude-plugin/`, so they are not installed.
- `.spoolway/`, `scripts/` and `.github/` make this repository a consumer of its own types.

## Install

The repository publishes one catalogue, `.claude-plugin/marketplace.json`, named
`spoolway-companion`, with one plugin, `spoolway-companion`. A consumer keeps no plugin list and no
pin: its `.claude/settings.json` holds only the github pointer to the catalogue and the id to
enable, and the revision it took is the one `.spoolway/plugin.lock` records.

```json
{
  "enabledPlugins": { "spoolway-companion@spoolway-companion": true },
  "extraKnownMarketplaces": {
    "spoolway-companion": {
      "source": { "source": "github", "repo": "theTestTube/spoolway-companion" }
    }
  }
}
```

The install is the person's, once per machine, at user scope, so every checkout and worktree of
the machine shares one copy:

```bash
claude plugin marketplace add theTestTube/spoolway-companion --scope user
claude plugin install spoolway-companion@spoolway-companion --scope user
```

Then enable it per project (the `enabledPlugins` line above), restart Claude Code, and run
`/spoolway-companion:spoolway-types`, which writes the types at the installed revision and records
that revision in `.spoolway/plugin.lock`.

The companion's revision is every merge to `main`. To move a consumer to a newer one, update the
catalogue and the plugin, restart Claude Code, and retake the types:

```bash
claude plugin marketplace update spoolway-companion
claude plugin update spoolway-companion@spoolway-companion --scope user
```

`/spoolway-companion:setup` does the consumer's side for a person: on a first install it interviews
them and writes the pointer, the id, the types and the consumer files below, and prints the two
install commands; `bump` runs the two update commands, retakes the types and never edits
`.claude/settings.json` (see Skills). An inline `spoolway-companion` marketplace of an older
consumer (`source: settings`, with a plugin list and a `sha`) is reported and left as it is: it
collides with the catalogue's name, so the consumer replaces it by the pointer by hand.

A plugin that is not installed cannot ship the hook that says so, so a consumer owns that hook:
`claude-plugin/templates/claude/hooks/missing-plugin.sh` is copied to
`.claude/hooks/missing-plugin.sh` and registered as a SessionStart hook in `.claude/settings.json`
(the snippet is in the file's header). When a plugin the project enables is not installed, it tells
the person the `claude plugin marketplace add` and `claude plugin install … --scope user` commands.
It writes nothing and never blocks the session. Its test is `tests/spoolway-missing-plugin.test.sh`.

## Extension points

The pipelines name behaviours, never repositories. A consumer fills them in. The full contract of
each, the three-tier rule behind them and how `companion.env` is read are in
[docs/extension-points.md](docs/extension-points.md); multi-repo tasks in
[docs/multi-repo.md](docs/multi-repo.md); the GitHub issue hook in
[docs/issue-tracking.md](docs/issue-tracking.md); the setup skill in
[docs/setup.md](docs/setup.md).

| Extension point | What the consumer provides | Without it |
|---|---|---|
| `scripts/spoolway/checks.sh` | the repository's checks, the same lines as its CI | required |
| `scripts/spoolway/handover.sh` | push the branch and open the pull request | required |
| `scripts/spoolway/extra-worktree.sh`, `extra-handover.sh`, `extra-cleanup.sh` | a worktree, a pull request and a cleanup in each extra repository a task's `repos` names | write them to pass at once and block a task naming more than one repository, as this repository's own do |
| `scripts/spoolway/materializing-bind.sh`, `materializing-backing.sh`, `materializing-drafts.sh`, `materializing-gates.sh`, `materializing-handover.sh` | the Materializing steps' checks and handover, exchanging files with the lanes | required by a consumer that runs Materializing |
| `.spoolway/companion.env` | `KEY=value` lines read by the shipped scripts (below); an environment variable that is set and not empty wins | each key's own, in the table below |
| `docs/agents/projects.md` | the projects, the rule for `repos`, and any private feedback repository | the project is the repository itself |
| `.spoolway/hooks/github.sh` | the issue-tracking hook, copied from `claude-plugin/templates/` | tasks still run; no `spoolway:*` labels, no close on merge, no issue reads |
| `.claude/hooks/missing-plugin.sh` | the SessionStart hook that names a required plugin that is not installed, copied from `claude-plugin/templates/claude/hooks/` and registered in `.claude/settings.json` | nothing says a plugin is missing: the session just lacks it |

`companion.env` keys:

| Key | Read by | Meaning |
|---|---|---|
| `PAGES_DIR` | `pins.sh`, the prompts | a directory of pages that cite code and carry pins; unset means no page step runs and `pins.sh` passes at once |
| `PAGES_GATE` | `pins.sh` | the command that emits the drift record contract (default `scripts/gates/run.sh stale-pages`); a repo with no wiki names `scripts/spoolway/stale-pages-stub.sh` |
| `PAGES_LOG`, `PAGES_COMPILE_PATTERN` | `pins.sh` | the log a page compile writes, and the pattern of its entry; no log means no check that a page was compiled, not edited by hand |
| `PAGES_COMMIT_PREFIX` | `pins.sh` | the subject prefix of the pin commit |
| `PIN_DRIFT_PROTECTED` | `hooks/pin-drift` | the path writes are denied under while the install differs from the lock; unset means no denial |
| `RUN_REPORT_REPO` | `run-report.sh` | where run reports are filed; unset means the run's own repository |
| `FINDINGS_REPO` | `findings.sh` | where the weekly digest lives; unset means the run's own repository |
| `MATERIALIZING_REPO` | `/spoolway-companion:setup` only | the repository of Materializing's specs; the prompts read it from `docs/agents/projects.md`, where setup writes it too |

`COMPANION_ENV_FILE` names another file than `.spoolway/companion.env`.

## Hooks

`claude-plugin/hooks/pin-drift` compares the installed commit of `spoolway-companion`
(`gitCommitSha` of its user-scope record in `$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json`)
with the `revision` in the project's `.spoolway/plugin.lock`. It reads nothing from
`.claude/settings.json`. When the record is absent or lacks `gitCommitSha`, it falls back to the
version in `claude plugin list --json`, which for a version-less plugin reports `<sha12>[-suffix]`.
If neither source can decide, the hook says so. A project with no lock, or a lock of another
plugin, has nothing to compare and the hook stays silent.

- **SessionStart** (startup, resume, clear, compact): on drift, it prints the user-scope
  `claude plugin marketplace update` and `claude plugin update … --scope user` commands, or
  `/spoolway-companion:setup bump` when the install is the newer one, and, when
  `PIN_DRIFT_PROTECTED` names a path, tells the agent not to write there.
- **PreToolUse** (`Write`, `Edit`): denies writes under `PIN_DRIFT_PROTECTED` while drift persists.
  `SPOOLWAY_COMPANION_WIKI_PIN_DRIFT_BLOCK=false` in the environment Claude Code starts in (not a
  `companion.env` key) turns the deny into a warning that names the drift and the commands; any
  other value, or none, denies.
  It recomputes drift on each call, so the gate lifts once the install matches.

The hook never blocks the session. It cannot report its own missing install, because no hook runs
until the plugin is installed: that is the consumer-owned `missing-plugin.sh` hook of Install. Run
the tests with `tests/pin-drift.test.sh` (needs `bash` and `jq`).

## Skills

**`/spoolway-companion:setup [bump | spoolway [<version>]]`**, which only a person can start, sets a consumer up. Detection runs
first and every question the disk answers is skipped; the interview then goes topology, pipelines,
issue tracking, destinations, wiki, then the `checks` and `handover` commands, and ends with a
summary the person confirms. It never overwrites a consumer file: in an existing
`.claude/settings.json`, `.spoolway/config.toml` or `.spoolway/companion.env` it only adds missing
keys or entries, and reports a differing value. It never writes a path `plugin.lock` lists but
through `types.sh write`, and leaves everything uncommitted on a branch. A consumer whose types
another plugin owns is reported, and the companion goes in beside it without touching that
plugin, its entry, its lock or its gate. It adds to a new consumer's settings only the github
pointer to the catalogue and the `enabledPlugins` id, when missing, and prints the user-scope
install commands; an inline entry is reported and left as it is. Given `bump`, it updates the
catalogue and the plugin at user scope, retakes the types, adds what is missing and prints a diff
for every copied template that changed, and it never edits `.claude/settings.json`. Given `spoolway` or a release
number instead, it changes no file of the checkout: it reads the gap between the installed spoolway and the latest
release (or the one named, forward or back), probes that release's binary against the checkout
without installing it, maps the breaking changes onto the checkout's files, and drafts the runs
the gap needs (Developing, Materializing, Architecting or Feeding-back) under `./.scratch/`. A
rollback first proposes unqueueing every task and stops unless the person opts in in words. The
install, the dispatcher, the `sync` and the reload stay the person's. Its mechanical half is
`skills/setup/setup.sh` (`detect`, `plan`, `apply`, `labels`, `bump`); a consumer that
takes Materializing gets its five `materializing-*` scripts from the templates.

**`/spoolway-companion:spoolway-repair <task-id>`**, which only a person can start, diagnoses a doomed spoolway task, salvages what cleanup would destroy, and advances or retreats it with the person. has no description and is hidden from the model, so a session that
never invokes it carries no trace of it. Its mechanical reads live in
`skills/spoolway-repair/repair.sh`, which the skill calls:

- `repair.sh diagnose <task>` writes nothing and prints the stage, loops, plain-resume route,
  handoff notes for a person, criteria, branch state, scratch files, dispatcher and keep-open marker
  as one JSON object.
- `repair.sh salvage <task>` copies the task's scratch space and command-step logs to
  `<main checkout>/.scratch/spoolway/<task>/{scratch,commands}` (the folder must be git-ignored),
  and drafts under `drafts/` every handoff note that asks a person to post or open something.
  It keeps the task document there too, as `task.md`, and, while the task stands on `blocked`, its
  diagnosis as `first-diagnosis.json`: written once, never replaced by a later salvage, and read
  back by `record`. Nothing is posted.
- `repair.sh choose <task>` writes nothing and prints the recommended road, advance or retreat, with
  its reason and conditions, the open findings and the step an advance resumes at.
- `repair.sh advance <task> [<step>] [--confirmed "<words>"]` prints the resume command at that step
  with its status-log message, or why it is refused. A step past a judgment that has not passed is
  the one-way door: no command until salvage is complete and the person's words are passed.
- `repair.sh retreat <task>` prints the retreat's steps in order (comment, commit of loose work, push, check that the
  remote holds the tip, plain `queue unqueue`, check, label) and what the unqueue will leave. Under
  0.19.0 the unqueue deletes the worktree and the local branch with no commit first, hence the order;
  it is refused while a dispatcher runs.
- `repair.sh pushed <task>` says whether the remote branch holds every commit of the local one.
- `repair.sh record <task> <advance|retreat|door>` drafts the bound issue's comment, the pull
  request's repair section and one finding per pipeline or task-document defect. The cause is the
  one in `first-diagnosis.json`, whatever the task's stage is by then.

A subcommand that can read its call prints one JSON object. A refusal carries `refused` and exits
1, a task spoolway does not hold included (`unknown-task`); a call that cannot be read at all
(usage, a malformed id, an unknown step) prints one line on stderr and exits 2. `salvage` has stops
of its own, listed in the skill's step 2 (exit 3 when its folder is not git-ignored), and `pushed`
exits 1 with `ok: false` until the remote holds every commit.

The script resumes, unqueues, pushes and posts nothing: it prints commands, each checked against the
binary's `--help` at run time, and the skill runs them on the person's word.

It reads spoolway's formats from the binary and needs `bash`, `jq`, `git` and `spoolway` 0.19.0.
`tests/spoolway-repair.test.sh` replays it offline on a fixture of the 2026-10-07 incident task and
on two synthetic tasks written as the Developing task template writes them
(`tests/fixtures/spoolway-repair/`), under a stub `spoolway` and `gh`.

## Pipeline types

spoolway reads only the checkout, so each consuming repository carries a tracked copy of the
types, written by the plugin at the revision it records in `.spoolway/plugin.lock`:

- `claude-plugin/spoolway/types/` mirrors the consumer path for path, except that `setup/` is the
  consumer's `.spoolway/`: a nested `.spoolway/` would be refused once this repository is a
  spoolway project itself. `types.manifest` lists every path with its mode and SHA-256, as
  `git ls-tree` does; regenerate it with
  `bash claude-plugin/spoolway/types.sh manifest > claude-plugin/spoolway/types.manifest`.
- **`/spoolway-companion:spoolway-types`**, started by a person in the consumer's checkout, runs
  `types.sh write`. It takes the revision from the install record of the copy it runs from and
  reads nothing from `.claude/settings.json`, so a newer revision needs the install updated and
  Claude Code restarted first. It writes every path, deletes the ones the previous lock listed and this
  revision dropped, and records the revision and each path's hash in `.spoolway/plugin.lock`.
  The lock carries no date: the same revision written twice changes nothing.
- **A consumer that runs only some of the types** declares them in `.spoolway/types.subset`, one
  consumer path per line (`#` starts a comment, blank lines are ignored). `types.sh write` then
  writes, locks and deletes only those paths, and refuses a path the shipped `types.manifest` does
  not list. The file belongs to the consumer and the plugin never writes it; without it every path
  is taken.
- The pipeline files are identical in every consumer. A repository's differences live behind the
  extension points above.

`tests/spoolway-setup.test.sh` runs `setup.sh` against throwaway consumers with a stub `claude`
in a throwaway `CLAUDE_CONFIG_DIR` and a fake `gh` whose calls it compares byte for byte.
`tests/spoolway-extra-repos.test.sh` runs the `extra-*` templates in a task worktree of a consumer
with an extra repository, against bare remotes and a fake `gh`.

Run the tests with `tests/spoolway-types.test.sh` (needs `bash`, `git`, `jq` and `sha256sum`).

### This repository is a consumer of its own types

- **The take is a subset.** `.spoolway/types.subset` names the three pipelines this repository
  dispatches (developing, developing-sonnet-review and materializing), with their prompts and task
  templates and the shared scripts.
- **The lock names an earlier commit.** A lock cannot name the commit that contains it, so
  `.spoolway/plugin.lock` names a commit already on `main`, the one the install was at when the
  types were taken. A change to `claude-plugin/spoolway/types/` therefore lands in two steps: that
  pull request, then a retake (the new `main`, the install updated at user scope, a restart,
  `/spoolway-companion:spoolway-types`) in the next.
- **What stays this repository's own:** `checks.sh` (`tests/*.test.sh` and
  `spoolway pipeline check`), `handover.sh`, the three `extra-*.sh` (this repository has no extra
  repository, so they pass at once and block a task whose `repos` names more than one), and
  `scripts/gates/run.sh`.
- **CI.** The `Gates` job of `.github/workflows/ci.yml` installs the spoolway release and runs the
  lines of the `gates` block of `scripts/spoolway/checks.sh`; `tests/spoolway-developing.test.sh`
  fails when the two differ.

### The weekly Feeding-back batch

The `feeding-back` pipeline turns the week's run reports and findings into triage issues. Its
`rotate` step (`scripts/spoolway/feeding-back.sh rotate`, a command with no model, shipped from
`claude-plugin/spoolway/types/scripts/spoolway/` like `collect.sh`: this repository's copy comes
back from `types.sh write` at the next retake, so none is checked in until then) runs after
`counts`: it opens the next "Weekly digest <ISO week>" issue in the project's repository unless a digest
other than the processed one is open, then closes the processed one (the issue the task is bound
to by `ticket:`). Each project therefore has one digest open, no lane opens or closes one, and a
rerun changes nothing. `findings.sh` finds the digest as the open issue whose title starts with
"weekly digest". The first digest of a project is opened by a person, once.

Between `intake` and `route`, the `architecture` step runs `improve-codebase-architecture` over the
grouped signals (Opus, high effort). It writes the HTML report to the scratch space and holds the
interview over the chosen candidate in the lane's pane; with nothing architectural it passes and
asks nothing. `route` marks the groups the review answers `architecture: yes`, and
`feeding-back.sh apply` appends the review's summary to the issue it opens from them.

Participant feedback is one more source (version 1.3): `intake` reads the issues of the public
feedback repository new since the digest was opened and the project's `relayed` issues, named in
the task document's Context, as data, and lists them in `participants.md` by reference alone.
`feeding-back.sh reply`, run by `route`, answers them under the relay rule: one fixed
acknowledgement with the AI-generated disclaimer on a public issue, labels and no comment on a
`relayed` issue, `ready-for-human` and no reply for a case needing judgment. `apply`, `reply` and
`counts` refuse to run when a line of a participant issue's body appears in a ledger or in a body
they would post, so no participant text reaches a finding, a routed issue, the counts or the log.

Open pull requests are summarised on the digest (version 1.4): `intake` lists every open pull
request of the project's repositories, those `docs/agents/projects.md` names and the digest's
repository without that file, in `pulls.md`, each with its age, merge state, last activity, the task
or issue behind it and what it waits on. `feeding-back.sh counts` appends the list to its comment
on the digest, so a pull request nobody has touched for months surfaces in the weekly batch. A pull
request is not a finding: it is counted in neither `received:` nor the route, and no lane writes on
one.

What queues the batch is a job in the machine's jobs file, never tracked
(`~/.spoolway/<project>/jobs.toml`; `timeout 30 spoolway jobs contract < /dev/null` prints the
format). A person writes it from the jobs screen for this project:

```toml
[jobs.weekly-feeding-back]
schedule = "0 7 * * mon"
pipeline = "feeding-back"
routine = "weekly-feeding-back"
base = "main"
```

`routine` is a folder under `.spoolway/routines/` (or a `.md` file there) holding the Feeding-back
task document from `.spoolway/templates/tasks/feeding-back.md`, bound by `ticket:` to the open
digest. The routine's task names a fixed digest, so each week's `ticket:` must be that week's
digest: until the job can name "the open digest", a person points the routine at it after the
first run, or the batch is queued by hand.

## Dependencies

| Dependency | Licence | Used for | Required |
|---|---|---|---|
| [spoolway](https://github.com/marvingygas/spoolway) | MIT | the dispatcher that runs the pipelines | yes |
| [mattpocock/skills](https://github.com/mattpocock/skills) | MIT | the skills the lanes start (`wayfinder`, `grilling`, `code-review`, `implement`, …) | yes |
| [memex](https://github.com/nicosuave/memex) | MIT | the read-only session-history search of the `recall` steps | no: a recall step passes without it |
| [llm-wiki](https://github.com/nvk/llm-wiki) | MIT | the page write path, when `companion.env` names a pages directory | no |
| [herdr](https://github.com/herdrdev/herdr) | Apache-2.0 | the terminal panes spoolway opens its lanes in | as spoolway needs |

## Licence

MIT, see [LICENSE](LICENSE). Contributions are accepted under the same licence (inbound =
outbound); see [CONTRIBUTING.md](CONTRIBUTING.md), which also holds the content rule.
