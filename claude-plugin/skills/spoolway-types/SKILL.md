---
name: spoolway-types
disable-model-invocation: true
---

# spoolway-types

A person starts this in a consuming repo's checkout to take the spoolway pipeline types from this plugin, at the revision of the installed copy, recorded in `.spoolway/plugin.lock`. What it writes lands by pull request, like any change to the tracked setup.

1. Run `bash <this skill's base directory>/../../spoolway/types.sh write` from the checkout's root. It writes the pipelines, prompts and task templates into `.spoolway/`, the shared scripts into `scripts/spoolway/`, and the revision with a hash per path into `.spoolway/plugin.lock`. A path the previous lock listed and this revision no longer ships is deleted. When the checkout has a `.spoolway/types.subset`, it writes only the paths that file names, and a path it names that the revision no longer ships is a refusal.
2. On a refusal it writes nothing: show its message and stop. A copy with no install record means the plugin is not installed: give the person the user-scope install command it printed (`claude plugin install spoolway-companion@spoolway-companion --scope user`), and say a restart of Claude Code comes after it. Do not edit the lock or the files to get past a refusal.
3. Show `git status --short` and `git diff --stat`, then run `timeout 60 spoolway pipeline check < /dev/null` and `timeout 120 spoolway doctor < /dev/null`, and show what each printed.

Done when the three outputs are shown. Commit and push only when the person asks. The repo's own scripts with the same names, such as `scripts/spoolway/checks.sh`, are never written here: a repo's differences live in them.
