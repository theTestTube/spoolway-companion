# Extension points

The companion's pipelines name behaviours, never repositories, products or paths of one project.
Whatever is a consumer's own sits behind an extension point, and this page lists every one of them
with what it assumes of the consumer. A consumer that fills them in from this page needs to read
none of the companion's scripts.

Related pages: [multi-repo.md](multi-repo.md) (the `extra-*` steps and `repos`),
[issue-tracking.md](issue-tracking.md) (the `github.sh` hook) and [setup.md](setup.md) (the setup
skill that writes the consumer side).

## The three-tier rule

Every consumer-specific thing takes one of three forms, and only these three:

1. **A behaviour is a step with a neutral name that calls a consumer script of the same name.**
   The pipeline says *when* (`checks` after `implement`, `extra-handover` before `handover`); the
   consumer's script says *what*. The companion ships no stub for these scripts, because
   `types.sh write` overwrites every path its manifest lists: a consumer's own copy would be
   replaced at the next pin bump. A consumer with nothing to do there writes a script that passes
   at once.
2. **A task parameter is a pass-through frontmatter key.** spoolway keeps a key it does not know
   verbatim in the task document; the companion's scripts and prompts read it, and so may the
   consumer's scripts. `repos` is the main one (see [multi-repo.md](multi-repo.md)).
3. **A per-consumer value is one `KEY=value` line in `.spoolway/companion.env`**, and an
   environment variable of the same name wins. This is for values that are the same for every
   task of the project: where reports go, where pages live.

## `.spoolway/companion.env`

A tracked file at the root of the consumer's checkout. It holds no secrets: anything private stays
in the environment of the machine that runs the dispatcher.

How the shipped `lib.sh` reads a key (`companion_env <KEY> [<default>]`):

- An environment variable of that name wins, but only when it is set **and not empty**.
- Otherwise the **last** line starting `KEY=` in the file gives the value: the text after the
  first `=`, with a trailing carriage return and trailing blanks taken off, then one pair of
  surrounding single or double quotes. Quote a value whose trailing blank matters.
- The file is read with `grep` and never sourced: nothing in it runs, and nothing is expanded
  (`$HOME` stays the four characters `$HOME`). A consumer's own script may expand a value it reads.
- `COMPANION_ENV_FILE` names another file than `<checkout root>/.spoolway/companion.env`.
- With neither variable nor line, the caller's default is used, or nothing. What "nothing" means
  is the key's own, in the table below: some steps pass at once, some fall back to the run's own
  repository, none falls back to a repository or path the companion names.

The `pin-drift` hook has its own, smaller reader for its one key: the environment variable when not
empty, else the last `PIN_DRIFT_PROTECTED=` line of `.spoolway/companion.env` in the project
directory, trailing blanks, a leading `./` and a trailing `/` taken off. It does not follow
`COMPANION_ENV_FILE` and does not strip quotes, so write that value unquoted.

### Keys the shipped scripts read

| Key | Read by | Meaning | Without it |
|---|---|---|---|
| `PAGES_DIR` | `pins.sh`, the prompts | the directory of pages that cite code and carry drift pins, relative to the root | no page step runs; every `pins.sh` mode says so and passes at once |
| `PAGES_GATE` | `pins.sh` | the command that reports stale pages ([Pages](#pages)) | `scripts/gates/run.sh stale-pages` |
| `PAGES_LOG` | `pins.sh` | the log a page compile appends to | none: no check that a recompiled page was compiled, not edited by hand |
| `PAGES_COMPILE_PATTERN` | `pins.sh` | the `sed` pattern that, at the start of a log line the branch added, precedes the compiled page names | `## \[[0-9-]*\] compile \| ` (quote it in the file: it ends in a blank) |
| `PAGES_COMMIT_PREFIX` | `pins.sh` | the subject prefix of the pin commit | `docs(pages):` |
| `PIN_DRIFT_PROTECTED` | `hooks/pin-drift` | the path under which `Write` and `Edit` are denied while the installed plugin differs from the revision in `.spoolway/plugin.lock` | no denial; the drift warning still shows |
| `RUN_REPORT_REPO` | `run-report.sh`, the Feeding-back intake (through `run-report.sh repo`) | the report repository, named `[HOST/]OWNER/REPO` as `gh --repo` takes it (a name, not a path or a URL), that run reports are filed in and read from | the run repository, as `gh` reads it from the checkout (`SPOOLWAY_REPO` when set); the step fails when `gh` cannot tell |
| `FINDINGS_REPO` | `findings.sh` | the repository, named `[HOST/]OWNER/REPO` as above, that holds the open "Weekly digest" issue | the run repository, as above; the step refuses when `gh` cannot tell |

The `PAGES_*` keys other than `PAGES_DIR` matter only once `PAGES_DIR` is set.

`CI_WAIT_SECONDS` (default 2100) and `CI_POLL_SECONDS` (default 30) tune the `ci` step's wait. They
are read from the environment only, not from `companion.env`; keep the `ci` step's `timeout:` above
the first.

### Keys a consumer adds for its own scripts

A consumer may add any key its own scripts read, with the same reader: source `lib.sh` and call
`companion_env MY_KEY`. The companion ignores keys it does not know. Typical ones: the repository
Materializing opens tickets in when it is not the run's own. The `extra-*` templates setup writes
read two: `EXTRA_REPOS`, the extra repositories, and `EXTRA_WORKTREE_ROOT`, the root their
worktrees are cut under ([multi-repo.md](multi-repo.md#the-companions-templates)); setup writes
both for a multi-repo, and with `EXTRA_REPOS` unset those scripts behave as a mono-repo's. When such a script cannot work without its key, it fails
with a line starting `ENVIRONMENT:` naming the key, rather than guessing a value: that way the task
blocks with a reason a person can act on.

## Consumer scripts behind the steps

Every one of these lives at `scripts/spoolway/<name>.sh` in the consumer, is executable, and is
the consumer's: the companion never writes or updates it.

### What every step script must do

- **Exit status.** Exit 0 passes the step. Anything else fails it, and a failure goes where the
  pipeline says: `checks` back to `implement`, `drafts` back to `tickets`, `gates` back to
  `document`. Every other step listed here has no `on_fail`, so a failure parks the task on
  `blocked` for a person (or, in an unattended run, the unblocker).
- **`ENVIRONMENT:` lines.** A failure that is not the code's fault (a missing tool, a missing key,
  no network) is reported on stderr in a line starting `ENVIRONMENT:`. The implementing and
  documenting lanes are told to block on such a line instead of trying to fix it, and the run
  report counts `checks` failures of this kind.
- **Arguments.** A step script takes only the arguments the pipeline passes. `lib.sh` has
  `no_arguments <step> "$@"`, which refuses any other.
- **Only inside its own step.** `own_step <step>` exits unless the task document's `stage:` is that
  step, so neither a lane nor a person runs a step's side effects by mistake. Call it after the
  arguments are read and before anything is written.
- **`skip_steps`.** A task may name steps in its `skip_steps` frontmatter list. A script whose step
  is named passes at once: `step_skipped "$SPOOLWAY_TASK_FILE" <step>`.
- **Environment.** spoolway runs a command step in the task's worktree with `SPOOLWAY_TASK_FILE`
  naming the task document. It does not hand a command step `SPOOLWAY_SCRATCH`; `task_scratch
  "$SPOOLWAY_TASK_FILE"` derives the task's scratch space, where the lanes leave their files.
- **`lib.sh`.** The shipped `scripts/spoolway/lib.sh` is meant to be sourced by consumer scripts:
  `companion_env`, `frontmatter_value`, `frontmatter_list`, `frontmatter_list_has`,
  `frontmatter_has_key`, `step_skipped`, `own_step`, `no_arguments`, `task_scratch`, `task_base`,
  `task_starts_from`, `task_unchanged`, `branch_base`, `on_branch`, `open_pull_request`,
  `conventional_title`, `closing_keywords`, `strip_ai_trailer`, `issue_url` and `issue_repo`. Its
  header comment on each says what it does.

### Developing

| Script | When it runs | What the consumer provides | Without anything to do |
|---|---|---|---|
| `extra-worktree.sh` | first step | a worktree on the task's branch name in each extra repository `repos` names | pass at once; see [multi-repo.md](multi-repo.md) |
| `checks.sh` | after `implement` | the repository's checks, the same commands its CI runs on a pull request, in the task's worktree; with pages, also `pins.sh check` | required: a repository with no checks still has to say so in a script that passes |
| `extra-handover.sh` | after `review`, before `handover` | push the branch and open the pull request in each extra repository, and wait for what must be green first, within the step's `timeout` (45m, the `ci` step's) | pass at once |
| `handover.sh` | after `extra-handover` | squash, push and open the task's pull request (typically `spoolway stack`), with no AI attribution and no closing keyword in its body; fail when no pull request is open afterwards | required |
| `extra-cleanup.sh` | after `report`, before `collect` | remove the extra worktrees once their branches are on the remote; leave alone a worktree with unpushed work, and still pass | pass at once |

The companion's own `scripts/spoolway/checks.sh` and `handover.sh` are worked examples of both
required scripts. Its own `handover.sh` also refuses a title that is not Conventional Commits and a
body with a closing keyword before anything is pushed, takes spoolway's attribution trailer off the
pull request body, and renders the task's `requires:` as a `## Waits on` section.

The shipped steps `pin` (`pins.sh pin`), `ci` (`ci.sh`), `signals` (`run-report.sh`) and `collect`
(`collect.sh`) need nothing from the consumer beyond the keys above.

### Materializing

The five `materializing-*` scripts ship with the Materializing pipeline in
`claude-plugin/spoolway/types/scripts/spoolway/`, so a consumer that takes the pipeline through
`/spoolway-companion:spoolway-types` has them without writing any. Each exchanges files with a
lane through the task's scratch space; the formats below are what the shipped prompts write and
read. `materializing-gates.sh` is the one that reads the consumer: `MATERIALIZING_GATES` and
`MATERIALIZING_ALLOWED` in `.spoolway/companion.env` ([README](../README.md)).

| Script | Step | Reads | Writes | Fails to |
|---|---|---|---|---|
| `materializing-bind.sh` | `bind` | the task document | nothing | blocked |
| `materializing-backing.sh` | `backing` | `recall.candidates.md` | `recall.md`, `recall.dropped.md` | blocked |
| `materializing-drafts.sh` | `drafts` | `tickets.md`, `drafts/<id>.md`, `breakdown.md` | the drafts into the project's `pending/`, all or none; on failure `drafts.problems.md` | `tickets` |
| `materializing-gates.sh` | `gates` | the branch | on failure `gates.problems.md` | `document` |
| `materializing-handover.sh handover` | `handover` | the branch | the pull request | blocked |
| `materializing-handover.sh pin` | `pin` | the branch | the pin commit | blocked |

- **`bind`** refuses a task that is not bound by `ticket:` to an open issue, or that lacks
  `close_on_merge: false`. A spec outlives the task that cuts it, and spoolway validates no
  pass-through key at queue time, so this is where a mis-queued task stops before any lane spends
  anything.
- **`backing`** is the gate between session history and the interview. The `recall` lane writes
  one candidate per line:

  ```text
  - <the claim, one sentence> | wiki: <page id> | ref: <#N, owner/repo#N, an issue URL, or path[:line]>
  ```

  `wiki:` is a page file name without `.md` under `PAGES_DIR`; `ref:` takes several references
  separated by commas. The script admits a candidate only when the repository backs it (for
  instance, the page exists and at least one reference is a real issue or a tracked file that is
  not itself a page), writes the admitted lines to `recall.md`, which the grill reads, and the
  others with their reason to `recall.dropped.md`. It passes whatever it admits, none included. A
  consumer without pages decides its own backing rule and says so in the script.
- **`drafts`** checks what the `tickets` lane left and copies it into `pending/`. `tickets.md` has
  one line per ticket opened:

  ```text
  - <issue URL> | draft: <task id>
  - <issue URL> | draft: none
  ```

  and `drafts/<task id>.md` holds one Developing task document per `draft: <task id>` line.
  `draft: none` is for a ticket another project dispatches. Worth checking, as a minimum: each
  ticket once and never the spec itself; a draft for every ticket of this project; each draft
  bound by `ticket:` to its ticket's full URL, on `pipeline: developing`, with `base:`, a
  Conventional Commits title, no `close_on_merge` and no closing keyword; its title and `repos`
  matching the ticket's line in the grill's `breakdown.md`; and `spoolway task contract --from
  <dir>` accepting the set. It never queues anything. What it refuses goes to `drafts.problems.md`,
  which the lane reads when it is sent back.
- **`gates`** runs the repository's own gates on what `document` wrote, plus guards no gate sees
  from the tree alone (nothing changed outside where decisions and terms are recorded; no lane
  moved a drift pin). With pages, it runs `pins.sh check all`. What failed goes to
  `gates.problems.md`. The `document` lane runs `materializing-gates.sh preview` before it reports:
  the same checks, reported, with nothing written. The pipeline file never passes `preview`.
- **`handover` and `pin`** are one script with two modes, because a run that decided nothing to
  document has an empty diff: both modes then pass at once. Otherwise `handover` runs
  `scripts/spoolway/handover.sh` and `pin` runs `scripts/spoolway/pins.sh pin all`.

The Materializing prompts also read `docs/agents/projects.md` ([below](#docsagentsprojectsmd)).

### Pages

A consumer that keeps pages of prose citing its code (a wiki, design notes) sets `PAGES_DIR`, and
the pipelines then make every run answer for the pages its change made stale. `pins.sh` has three
modes:

- `pins.sh status`: what the gate says about this branch, and what the record says. Always exits
  0; a lane runs it to see what it owes.
- `pins.sh check`: the same, failing unless every red page is declared `holds` in the record at a
  commit its cited paths have not changed since. The consumer's `checks.sh` calls it.
- `pins.sh pin`: the `pin` step after `handover`. One commit that moves `verified_commit` to the
  squashed commit and `verified:` to the day on the pages declared `holds`, and changes nothing
  else, then a plain push.

A second argument `all` runs the full gate instead of the branch's scope: Materializing uses
`check all` and `pin all`, and its `pin` fails unless the full gate ends green.

`PAGES_GATE` is the consumer's command. `pins.sh` runs it in records mode, with
`STALE_PAGES_RECORDS=1` in the environment (`STALE_PAGES_SCOPE=branch`, or unset for the full gate,
and `STALE_PAGES_BASE` the commit to compare against). It prints one record per page, one line of
tab-separated fields, and a closing `=== GREEN` or `=== RED` line:

```text
<slug>\t<pin>\t<pin-in-history>\t<deleted>\t<changed>\t<owed-by>\t<compile-proof>
```

Each `\t` is a literal tab. The fields are:

- `slug` — the page file name without `.md`.
- `pin` — the page's 40-hex pin, or empty.
- `pin-in-history` — `true` or `false`: whether the pin is an ancestor of HEAD. A pin that is not
  is a field, never a cited path.
- `deleted`, `changed` — the cited paths deleted or changed since the pin, `;`-separated, empty
  when none.
- `owed-by` — `branch` (this branch made the page stale), `base` (only the base carries it:
  reported, never blocking) or `none` (not stale). A record is RED when `owed-by` is `branch` or
  `base`, GREEN when it is `none`.
- `compile-proof` — `yes`, `no` or `n/a`.

A consumer without a wiki names `scripts/spoolway/stale-pages-stub.sh` as `PAGES_GATE`: it answers
the records mode with an empty page set and GREEN. The record the lanes write is `stale-pages.md`
in the task's scratch space, one line per page:

```text
<page slug> | holds | <commit the page was read at> | <why the page still says what the code does>
<page slug> | no-longer-holds | <commit> | <what the page says that the change made false>
```

The prompts' page-writing text runs only when `PAGES_DIR` is set; without it no lane writes a
page. A page write path such as llm-wiki is an optional dependency.

## Pass-through frontmatter keys

spoolway's own keys are listed by `spoolway task contract`. These are the companion's, which
spoolway keeps verbatim and never validates:

| Key | Read by | Meaning |
|---|---|---|
| `repos` | the `extra-*` scripts, the Developing prompts, `materializing-drafts.sh` | the repositories the task changes; opaque to the companion ([multi-repo.md](multi-repo.md)) |
| `skip_steps` | every step script and prompt | steps that pass at once for this task. `collect` is never skipped |
| `implementer` | the `implement` and `implement-spec` prompts | which of the two builds the task; the other passes at once |
| `requires` | `handover.sh` | what the task waits on in another project, rendered as `## Waits on` in the pull request body |
| `close_on_merge` | the `github.sh` hook, `materializing-bind.sh` | `false` keeps the bound issue open when the pull request merges (a spec) |

A consumer's own script may read further keys of its own the same way (`frontmatter_value`,
`frontmatter_list`).

## `docs/agents/projects.md`

The project catalogue, read by the Developing and Materializing prompts in place of any list the
companion could carry. Without the file, the project is the repository itself: tickets open in it,
and `repos` names nothing else. With it, it holds:

- **The projects**: one row per project, with its repository, which queue dispatches its tasks
  (this one, this one as an extra repository of a task, or its own), and what it is.
- **The rule for `repos`**: which repository a ticket names when it changes what, and what the
  `extra-*` steps then do for it.
- **Where the extra worktrees live**, so the implementing and reviewing lanes edit each extra
  repository in its worktree and nowhere else.
- **Private repositories**: any feedback or other repository no lane may open an issue in, read
  for a ticket, or copy from.

The Materializing `tickets` lane opens each ticket in the repository of the project that will
dispatch it, as this file says, and leaves `draft: none` for a project dispatched elsewhere.

## `.spoolway/types.subset`

A consumer that runs only some of the pipelines lists the consumer paths it takes, one per line
(`#` starts a comment; blank lines are ignored). `types.sh write` then writes, locks and deletes
only those paths, and refuses a path the shipped manifest does not list. A path the previous lock
listed and the subset no longer names is deleted.

Nothing is pulled in for you: a pipeline's prompts, its task template and every shipped script its
steps run (`lib.sh` always, then `ci.sh`, `collect.sh`, `dod.sh`, `pins.sh`, `run-report.sh`,
`feeding-back.sh`, `findings.sh` as the steps name them) must each be listed. `spoolway pipeline
check` reports a step whose script or prompt is missing. Without the file, every path is taken.
The file is the consumer's: `types.sh` never writes it, and the setup skill writes it only when it is missing. The companion's own
`.spoolway/types.subset` is a worked example.

## The missing-plugin hook

`.claude/hooks/missing-plugin.sh` is a template under `claude-plugin/templates/claude/hooks/`.
The consumer copies it once and registers it by hand as a `SessionStart` hook in
`.claude/settings.json`; `setup apply` neither copies nor registers it. It reads `enabledPlugins`
in `.claude/settings.json` (a `false` in `.claude/settings.local.json` turns a plugin off), the
user's `installed_plugins.json`, and the `github` pointer of the marketplace for the
`claude plugin marketplace add` command it prints. It writes nothing and never blocks the
session. Without it, nothing tells a person that a plugin the project enables is not installed on
their machine: a missing plugin cannot ship the hook that would report it.

## The issue-tracking hook

`.spoolway/hooks/github.sh` and `.github/workflows/spoolway-issues.yml` are templates under
`claude-plugin/templates/`, copied once. See [issue-tracking.md](issue-tracking.md).
