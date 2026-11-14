---
name: setup
disable-model-invocation: true
---

# setup

A person starts this in a consuming repo's checkout to set it up for the companion, or to move it to a new companion revision. It asks, `setup.sh` beside this file finds and writes. Every file lands uncommitted on a branch; the person reviews it, commits and opens the pull request. Never commit, push or open a pull request here.

`setup.sh` never overwrites a consumer file: in a file that exists it only adds missing keys or entries, and a differing value is reported and left. The one value it changes is the `sha` of the companion's own entry, on a bump. Do not edit a file by hand to get past what it kept or refused.

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
   6. The commands the `checks` step runs, the ones your CI runs; the `handover` and `materializing-*` scripts are named in the summary when the companion has no template for them.
4. Write the answers to a file outside the checkout, one `key=value` per line: `topology` (`mono`|`multi`), `extra_repos` (space-separated), `worktree_root`, `repos_rule`, `pipelines` (space-separated, or `all`), `issue_tracking` (`yes`|`no`), `project_key`, `companion_sha` (the commit to pin; leave it out to pin the revision this installed copy is, which `setup.sh` reads from its install record), `wiki` (`yes`|`no`), `wiki_url`, `wiki_sha`, `wiki_ref`, one `checks=<command>` line per gate command, and the `companion.env` keys in upper case: `RUN_REPORT_REPO`, `FINDINGS_REPO`, `MATERIALIZING_REPO`, `PAGES_DIR`, `PAGES_LOG`, `PAGES_COMPILE_PATTERN`, `PAGES_GATE`, `PAGES_COMMIT_PREFIX`, `PIN_DRIFT_PROTECTED`. Leave out what was not answered.
5. Run `bash <base>/setup.sh plan <answers>` and, when issue tracking is on, `bash <base>/setup.sh labels <owner/repo>`. Show both as the summary of what will be written and created, and ask the person to confirm. On a no, change the answers and show the summary again.
6. On a yes: `bash <base>/setup.sh apply <answers>`, then `bash <base>/setup.sh labels <owner/repo> --create` when issue tracking is on. It creates only missing labels and never edits one. Show what each printed.
7. When it reports `docs/agents/issue-tracker.md` or `docs/agents/triage-labels.md` missing, or the tracker doc without its "Wayfinding operations" section, say so and offer to run `/setup-matt-pocock-skills`; run it only on the person's yes. Never edit those files here.
8. Show `git status --short`, every `to do:` line, and what to restart.

Done when the person has the branch with the files uncommitted and every `to do:` line in front of them.
