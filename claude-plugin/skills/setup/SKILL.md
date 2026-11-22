---
name: setup
argument-hint: "[<companion-sha> | spoolway [<version>]]"
disable-model-invocation: true
---

# setup

A person starts this in a consuming repo's checkout to set it up for the companion, to move it to a new companion revision, or to move spoolway itself to another release. The argument picks the road:

- a full commit sha: **A bump**
- `spoolway`, or a release number (`<version>`, with or without the `v`): **A spoolway update**, to that release, or to the latest when none is named
- nothing: **A first install**

It asks, `setup.sh` beside this file finds and writes. Every file lands uncommitted on a branch; the person reviews it, commits and opens the pull request. Never commit, push or open a pull request here.

`setup.sh` never overwrites a consumer file: in a file that exists it only adds missing keys or entries, and a differing value is reported and left. In a new consumer's `.claude/settings.json` it adds only the github pointer to the catalogue and the `enabledPlugins` id, when missing; an inline entry is reported and left, and a bump never edits that file. Do not edit a file by hand to get past what it kept or refused.

One part is the machine's, not the branch's. `setup.sh memex` writes memex's config (`~/.memex/config.toml`) and the user's systemd timer. None of it shows in `git status` or in the pull request, so plan it, show it and confirm it apart from the checkout's files. It follows the same rule: it adds what is missing, reports a differing value and keeps it, and it never removes a timer.

## A bump

When the person asks for the companion's newest revision, run `bash <this skill's base directory>/setup.sh bump` from the checkout's root and show everything it printed. It takes no revision and never edits `.claude/settings.json`: it updates the catalogue and the companion (and llm-wiki, when enabled) at user scope, retakes the types and the lock, adds what is missing, and prints a diff for every copied template that changed upstream: the person applies those by hand. A `to do:` line is the person's. End by naming what it says to restart. Then stop.

## A first install

1. Run `bash <base>/setup.sh detect` and read its facts. A question whose answer is already on disk is skipped: say what was found instead.
2. If `old plugin` names a plugin, say that another plugin owns this repo's types; the companion goes in beside it, and that plugin, its settings entry, its lock and its lock gate stay untouched. Its cut-over is separate work.
3. Interview the person, one question at a time, in this order, offering the answer you recommend:
   1. Mono-repo or multi-repo. For multi-repo: the extra repositories (`owner/repo`), the folder their worktrees live under, and the rule for a task's `repos`.
   2. Which pipelines to take (`architecting`, `developing`, `developing-sonnet-review`, `feeding-back`, `materializing`), or all of them.
   3. Issue tracking on GitHub, yes or no; when yes, the `owner/repo` of the project's issues.
   4. Where run reports and findings go, and the repository that holds Materializing's specs. A destination that must stay private goes into a machine-local file that `COMPANION_ENV_FILE` names, never into an answer.
   5. A wiki, yes or no. When yes: its pages directory, its log file, the pattern of a compile entry in the log, its gate command, its commit prefix; and whether to add llm-wiki (the `owner/repo` of its catalogue).
   6. The commands the `checks` step runs, the ones your CI runs; the `handover`, `extra-*` and `materializing-*` scripts are written from the companion's templates, and named in the summary when it has none.
   7. Memex upkeep, only when `detect` shows `memex` on the PATH. Skip it when `memex schedule` is already `boot` or `hourly` and `memex embeddings` is neither `unset` nor `false`: say what was found. Otherwise ask how the memory index's vectors are kept current, with `memex vectors` and `memex mem available mb` in front of the person:
      1. `none`: nothing is scheduled; the person runs `memex index embed` by hand when search misses recent work. It is incremental: a pass with nothing new ends in under a second.
      2. `hourly`: a timer runs `memex index` every hour. Each pass loads the embedding model, about 3 GB of RAM for under a minute with the default model: take it only on a machine that keeps that much free.
      3. `boot`: one pass 3 minutes after the user session starts, when memory is freest. Recommend this one: it fits a machine that restarts often or is tight on memory. The index then lags until the next login or a manual `memex index embed`.

      A timer needs `embeddings` on, since it runs plain `memex index`; setup turns it on. When `memex vectors` is under 1000 the first pass is a full backfill (over an hour, about 4 GB): the plan says to run it by hand first and installs no timer.
   8. `auto_index_on_search`: ask the person to review it, and say what it does. With `true`, every `memex search` first re-scans the agent history (cached for `scan-cache-ttl`, an hour by default) and indexes what is new. With `false`, a search only reads, and the index is as fresh as the last indexing pass. Recommend the value that follows from question 7: `false` when a timer is scheduled, because the timer is then the one writer and a search does no scan work of its own (memex's own `daemon enable` makes the same choice and leaves the note "Background indexing handles freshness; avoid duplicate scan work during search"); `true` when nothing is scheduled, because nothing else would ever refresh the index. Name the cost of the recommendation: with `false` and `boot`, a search can miss the current session's work, and one `memex index` by hand brings it in. A value `config.toml` already holds is kept and reported.
4. Write the answers to a file outside the checkout, one `key=value` per line: `topology` (`mono`|`multi`), `extra_repos` (space-separated) and `worktree_root` (written to `companion.env` as `EXTRA_REPOS` and `EXTRA_WORKTREE_ROOT` for a multi-repo), `repos_rule`, `pipelines` (space-separated, or `all`), `issue_tracking` (`yes`|`no`), `project_key`, `companion_repo` (the catalogue's `owner/repo`; leave it out for `theTestTube/spoolway-companion`), `wiki` (`yes`|`no`), `wiki_repo` (the `owner/repo` of llm-wiki's catalogue) and `wiki_marketplace` (its name, `llm-wiki` by default), one `checks=<command>` line per gate command, and the `companion.env` keys in upper case: `RUN_REPORT_REPO`, `FINDINGS_REPO`, `MATERIALIZING_REPO`, `PAGES_DIR`, `PAGES_LOG`, `PAGES_COMPILE_PATTERN`, `PAGES_GATE`, `PAGES_COMMIT_PREFIX`, `PIN_DRIFT_PROTECTED`. Leave out what was not answered. The machine's two answers are `memex_schedule` (`none`|`hourly`|`boot`) and `memex_auto_index_on_search` (`true`|`false`); they stay in lower case, because an upper-case key goes to `companion.env`, and only `setup.sh memex` reads them.
5. Run `bash <base>/setup.sh plan <answers>` and, when issue tracking is on, `bash <base>/setup.sh labels <owner/repo>`. Show both as the summary of what will be written and created. When the memex keys were answered, also run `bash <base>/setup.sh memex plan <answers>` and show it apart, under "on this machine, not in the branch". Ask the person to confirm. On a no, change the answers and show the summary again.
6. On a yes: `bash <base>/setup.sh apply <answers>`, then `bash <base>/setup.sh labels <owner/repo> --create` when issue tracking is on. It creates only missing labels and never edits one. When the memex keys were answered, `bash <base>/setup.sh memex apply <answers>` last: installing the timer starts it, so one pass runs right away. Show what each printed.
7. When it reports `docs/agents/issue-tracker.md` or `docs/agents/triage-labels.md` missing, or the tracker doc without its "Wayfinding operations" section, say so and offer to run `/setup-matt-pocock-skills`; run it only on the person's yes. Never edit those files here.
8. Show `git status --short`, every `to do:` line (the memex ones too: they are not in `git status`), and what to restart.

Done when the person has the branch with the files uncommitted, what was written on the machine named apart, and every `to do:` line in front of them.

## A spoolway update

The checkout runs [spoolway](https://github.com/marvingygas/spoolway) at one release, the **As-Is** (`spoolway --version`). The **To-Be** is the release the person names, or the latest. The **gap** is everything the checkout holds that the To-Be changes. The **probe** is a copy of the To-Be binary in `./.scratch/`, hash-checked and never installed, that every later step runs against the checkout. This road reads, probes and drafts; it writes only under `./.scratch/spoolway-<As-Is>-to-<To-Be>/` (`<dir>` below) and changes no file of the checkout. Check `git check-ignore -q .scratch` first: when it fails, stop and ask the person to ignore `./.scratch/`.

`setup.sh` runs the update road's reads: each subcommand below (`bash <base>/setup.sh <subcommand>`, from the checkout's root) prints tab-separated lines the skill reads, writes only under `./.scratch/`, installs nothing and runs `sync` never. Read its output instead of typing the calls it replaces; a call it has no subcommand for is typed as follows. Every spoolway call is `timeout <n> spoolway … < /dev/null`, and `<n>` is as long as the command needs. The reads are `--version`, `whats-new`, `task contract`, `config contract|path|list`, `override list`, `pipeline list|show|check`, `doctor --no-live`, `queue list|show|route`, `lane`, `eval` and `sync --dry-run`. Run `sync` only with `--dry-run`: without a terminal it takes its write without asking. Read the board with `queue list` and `queue route`; `config override`, `config edit`, bare `spoolway queue` and bare `spoolway dispatch` open an editor or a screen, so leave them out.

**The person's word** is a yes, in this session, to the exact command, download or draft you have just shown. A download, an issue, a queue add and every move of a task (`queue pause`, `queue unqueue`, `resume`) each need their own.

**To do** lines are the person's: installing the binary, starting or stopping the dispatcher, taking a `sync`, changing an override, `spoolway dispatch reload`, pushing a branch. Name each as a `to do:` line with the exact command; the person runs it.

What past gaps hit is in [update-gotchas.md](update-gotchas.md): each trap with the command that shows whether it holds on this one. Read it before step 2.

### 1. Review the gap

1. As-Is, every copy, To-Be and direction: `setup.sh spoolway-version [<version>]` prints `as-is`, one `copy` line per binary `type -a spoolway` finds (a lane or a script can resolve another copy than the shell does), `to-be` (`named` or `latest`, with its tag) and `direction`. Forward when the To-Be is newer, backward when older, and when equal say so in one line and stop.
2. The releases in the gap: `setup.sh gap <to>` prints one `release` line per release after the older end up to the newer one, with its date and whether its notes hold a breaking-changes section, and saves each one's notes and `docs/migrations.md` at the tag (never the default branch) under `<dir>`. Forward, it reads migrations at the To-Be tag; backward, at the As-Is tag too: it documents what the release being undone changed. Read every file it saved.
3. Backward: read [update-rollback.md](update-rollback.md) now. Steps 2 and 3 run as written (steps, not the numbered items above); it replaces steps 4 and 5.

Done when you have stated, one line apiece:

- the As-Is, and every copy of spoolway `type -a` found
- the To-Be, and whether the person named it or it is the latest
- the direction
- each release of the gap by tag and date, each with its breaking-changes section read, and each `docs/migrations.md` section read with the tag it came from

### 2. Probe the To-Be binary

1. Show the person the exact download: the asset for this machine (`spoolway-<os>-<arch>`), `SHA256SUMS`, and `<dir>/bin/` as the destination. On the person's word run `setup.sh probe <version>`: it picks the asset by `uname`, downloads it with `SHA256SUMS`, runs `sha256sum -c --ignore-missing`, then `chmod +x`, links `<dir>/bin/spoolway` and checks that its `--version` prints the To-Be. When the session refuses the download, hand the person the `gh release download` command to run themselves and carry on from the files.
2. A `checksum MISMATCH` line stops the run: the script has deleted the download without a `chmod` or a link. Show it and use nothing from the download.
3. Run the To-Be's `whats-new --since <As-Is>` (forward) or the As-Is's `whats-new --since <To-Be>` (backward), and name every release it lists that step 1 did not, or the reverse.
4. `setup.sh probe-run [<dir>]` runs, for both binaries, from the checkout, `sync --dry-run`, `pipeline check` and `doctor --no-live`: the probe with `<dir>/bin` first on the `PATH`, every `companion.env` key unset in the environment. It saves each output and exit status under `<dir>/as-is/` and `<dir>/to-be/`, and prints one line per command with the difference classed **new**, **pre-existing** or **fixed** (or the outputs compared when both pass).
5. Find the checkout's own gates and tests from its checks script and its CI workflow, and run each under both binaries, with the checkout's machine-exported variables unset (`update-gotchas.md`, "Probing"). Save each log beside the others.
6. Take the class of each `probe-run` line and of each gate or test of item 5: **new** (the To-Be fails where the As-Is passes), **pre-existing** (both fail alike) or **fixed**. Read the saved outputs for the one-line cause.

Done when each command of items 4 and 5 has an output saved under both binaries, or a named reason and the word UNVERIFIED; every difference is classed with a one-line cause; and `type -a spoolway` and `spoolway --version` print what step 1 recorded.

### 2b. Discover the consumers

Run `setup.sh discover` and show every line it printed; the rules are in [discovery.md](discovery.md). Ask the person which consumers to map: a consumer they drop is not mapped, and steps 3 to 6 run for the confirmed set only.

Done when the person has confirmed, in words, the set of consumers to map, and you have repeated it back.

### 3. Map the gap

Match the gap to the checkout's own files: scripts, prompts, pipelines, CI workflows, docs, config keys, every place that pins the As-Is, and the queued task documents. Take the evidence from the probe's output, not from a search of the text: a search only hints at what the binary's check settles. Class each hit as **before** (it breaks under the To-Be and its fix also works under the As-Is, so it can land before any install) or **after** (it needs the To-Be: a sync, a pin, documentation, a reload).

Done when you have shown:

- one row per breaking change of every release in the gap: hit or no hit, with its evidence (the file and line, or the command and its output) and, for a hit, its class
- every file `sync --dry-run` lists, marked tracked or machine-local (`git check-ignore`), and every config key it adds, marked tracked or machine-only by the checkout's own machine-only gate
- every task `setup.sh queue-snapshot` shows (per project home: its state, whether a lane runs, its branch and the commits origin lacks), with its stage and step checked against `pipeline show` of the To-Be
- every active override (`override list`, in the folder `config path` names), with what each changes
- the verdict: **GAP** (at least one hit, one new failure or one task that cannot continue) or **no GAP**, with the commands that showed it

With no GAP, go to step 5.

### 4. Propose runs

Read [update-runs.md](update-runs.md). It holds the rule that picks Architecting, Materializing, Developing or Feeding-back, and how a draft is written and checked.

Done when each GAP finding is in one of three places, and the person has the list:

- a draft run, its id checked with `setup.sh fresh-id <id>…` (`free` means `task/<id>` is absent from origin), its pipeline, the finding it takes, the reason the rule gave, and its folder `<draft>` (`./.scratch/<issue>-<slug>/`), each passing `spoolway task contract --from <draft>` as `update-runs.md` says
- a `to do:` line, when the fix is the person's alone
- a stated reason it stays open

Nothing is queued, opened or posted until the person has given their word to that draft.

### 5. Hand over the person's steps

Give the person, in this order, every `to do:` line the gap needs:

1. install the To-Be binary: the same asset and hash check as the probe, or what `spoolway update --help` says for this install
2. stop every process still running the As-Is binary and start it again: the dispatcher, and any lane the person keeps
3. take `spoolway sync` in each place the drafts name, then read `git diff` of the tracked config before committing
4. `spoolway dispatch reload` once the pull request has merged

Done when every `to do:` line stands in that order, each with the command that shows it took (`spoolway --version`, `sync --dry-run` listing nothing, `pipeline check` and `doctor --no-live` as the probe left them), and the person has the list.

### 6. Verify

When the person says the install is done, run the `--version`, `sync --dry-run`, `pipeline check` and `doctor --no-live` of step 2 again, save them under `<dir>/after/`, and compare them with `<dir>/to-be/`.

Done when each output equals its probe counterpart, or each difference is named with its cause.
