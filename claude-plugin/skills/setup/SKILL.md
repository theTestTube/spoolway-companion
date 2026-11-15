---
name: setup
disable-model-invocation: true
---

# setup

A person starts this in a consuming repo's checkout to set it up for the companion, or to move it to a new companion revision. It asks, `setup.sh` beside this file finds and writes. Every file lands uncommitted on a branch; the person reviews it, commits and opens the pull request. Never commit, push or open a pull request here.

`setup.sh` never overwrites a consumer file: in a file that exists it only adds missing keys or entries, and a differing value is reported and left. The one value it changes is the `sha` of the companion's own entry, on a bump. Do not edit a file by hand to get past what it kept or refused.

One part is the machine's, not the branch's. `setup.sh memex` writes memex's config (`~/.memex/config.toml`) and the user's systemd timer. None of it shows in `git status` or in the pull request, so plan it, show it and confirm it apart from the checkout's files. It follows the same rule: it adds what is missing, reports a differing value and keeps it, and it never removes a timer.

## A bump

When the person names a new companion revision (a full commit sha), run `bash <this skill's base directory>/setup.sh bump <sha>` from the checkout's root and show everything it printed. It moves the pin, installs or updates the companion and llm-wiki for this project path, retakes the types and the lock, adds what is missing, and prints a diff for every copied template that changed upstream: the person applies those by hand. A `to do:` line is the person's. End by naming what it says to restart. Then stop.

## A first install

1. Run `bash <base>/setup.sh detect` and read its facts. A question whose answer is already on disk is skipped: say what was found instead.
2. If `old plugin` names a plugin, say that another plugin owns this repo's types; the companion goes in beside it, and that plugin, its settings entry, its lock and its lock gate stay untouched. Its cut-over is separate work.
3. Interview the person, one question at a time, in this order, offering the answer you recommend:
   1. Mono-repo or multi-repo. For multi-repo: the extra repositories (`owner/repo`), the folder their worktrees live under, and the rule for a task's `repos`.
   2. Which pipelines to take (`architecting`, `developing`, `developing-sonnet-review`, `feeding-back`, `materializing`), or all of them.
   3. Issue tracking on GitHub, yes or no; when yes, the `owner/repo` of the project's issues.
   4. Where run reports and findings go, and the repository that holds Materializing's specs. A destination that must stay private goes into a machine-local file that `COMPANION_ENV_FILE` names, never into an answer.
   5. A wiki, yes or no. When yes: its pages directory, its log file, the pattern of a compile entry in the log, its gate command, its commit prefix; and whether to install llm-wiki (its repository url and the commit to pin).
   6. The commands the `checks` step runs, the ones your CI runs; the `handover`, `extra-*` and `materializing-*` scripts are written from the companion's templates, and named in the summary when it has none.
   7. Memex upkeep, only when `detect` shows `memex` on the PATH. Skip it when `memex schedule` is already `boot` or `hourly` and `memex embeddings` is neither `unset` nor `false`: say what was found. Otherwise ask how the memory index's vectors are kept current, with `memex vectors` and `memex mem available mb` in front of the person:
      1. `none`: nothing is scheduled; the person runs `memex index embed` by hand when search misses recent work. It is incremental: a pass with nothing new ends in under a second.
      2. `hourly`: a timer runs `memex index` every hour. Each pass loads the embedding model, about 3 GB of RAM for under a minute with the default model: take it only on a machine that keeps that much free.
      3. `boot`: one pass 3 minutes after the user session starts, when memory is freest. Recommend this one: it fits a machine that restarts often or is tight on memory. The index then lags until the next login or a manual `memex index embed`.

      A timer needs `embeddings` on, since it runs plain `memex index`; setup turns it on. When `memex vectors` is under 1000 the first pass is a full backfill (over an hour, about 4 GB): the plan says to run it by hand first and installs no timer.
   8. `auto_index_on_search`: ask the person to review it, and say what it does. With `true`, every `memex search` first re-scans the agent history (cached for `scan-cache-ttl`, an hour by default) and indexes what is new. With `false`, a search only reads, and the index is as fresh as the last indexing pass. Recommend the value that follows from question 7: `false` when a timer is scheduled, because the timer is then the one writer and a search does no scan work of its own (memex's own `daemon enable` makes the same choice and leaves the note "Background indexing handles freshness; avoid duplicate scan work during search"); `true` when nothing is scheduled, because nothing else would ever refresh the index. Name the cost of the recommendation: with `false` and `boot`, a search can miss the current session's work, and one `memex index` by hand brings it in. A value `config.toml` already holds is kept and reported.
4. Write the answers to a file outside the checkout, one `key=value` per line: `topology` (`mono`|`multi`), `extra_repos` (space-separated) and `worktree_root` (written to `companion.env` as `EXTRA_REPOS` and `EXTRA_WORKTREE_ROOT` for a multi-repo), `repos_rule`, `pipelines` (space-separated, or `all`), `issue_tracking` (`yes`|`no`), `project_key`, `companion_sha` (the commit to pin; leave it out to pin the revision this installed copy is, which `setup.sh` reads from its install record), `wiki` (`yes`|`no`), `wiki_url`, `wiki_sha`, `wiki_ref`, one `checks=<command>` line per gate command, and the `companion.env` keys in upper case: `RUN_REPORT_REPO`, `FINDINGS_REPO`, `MATERIALIZING_REPO`, `PAGES_DIR`, `PAGES_LOG`, `PAGES_COMPILE_PATTERN`, `PAGES_GATE`, `PAGES_COMMIT_PREFIX`, `PIN_DRIFT_PROTECTED`. Leave out what was not answered. The machine's two answers are `memex_schedule` (`none`|`hourly`|`boot`) and `memex_auto_index_on_search` (`true`|`false`); they stay in lower case, because an upper-case key goes to `companion.env`, and only `setup.sh memex` reads them.
5. Run `bash <base>/setup.sh plan <answers>` and, when issue tracking is on, `bash <base>/setup.sh labels <owner/repo>`. Show both as the summary of what will be written and created. When the memex keys were answered, also run `bash <base>/setup.sh memex plan <answers>` and show it apart, under "on this machine, not in the branch". Ask the person to confirm. On a no, change the answers and show the summary again.
6. On a yes: `bash <base>/setup.sh apply <answers>`, then `bash <base>/setup.sh labels <owner/repo> --create` when issue tracking is on. It creates only missing labels and never edits one. When the memex keys were answered, `bash <base>/setup.sh memex apply <answers>` last: installing the timer starts it, so one pass runs right away. Show what each printed.
7. When it reports `docs/agents/issue-tracker.md` or `docs/agents/triage-labels.md` missing, or the tracker doc without its "Wayfinding operations" section, say so and offer to run `/setup-matt-pocock-skills`; run it only on the person's yes. Never edit those files here.
8. Show `git status --short`, every `to do:` line (the memex ones too: they are not in `git status`), and what to restart.

Done when the person has the branch with the files uncommitted, what was written on the machine named apart, and every `to do:` line in front of them.
