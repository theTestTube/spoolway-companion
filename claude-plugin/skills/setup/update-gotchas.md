# What past gaps hit

Reached from "A spoolway update". Each line was observed on an earlier gap and names the command that shows whether it holds on this one: a thing to check, not a promise. Release-specific facts are not kept here; the notes of the gap and the binary's `--help` hold those.

## Probing

- **A machine-exported variable beats a tracked file.** A suite that reads a key of `.spoolway/companion.env` fails locally when the shell exports the same name, and passes in CI. Run each gate and test under both binaries with those names unset: `env | grep -E '<names in companion.env>'`, then `env -u <name> …`.
- **Several copies of spoolway can be on the machine.** A lane or a script resolves the first one on its `PATH`, which may not be the shell's. `type -a spoolway`, and read `spoolway --version` from the copy a lane would use.
- **The registry may lag the release.** Install from the release's own assets (the same download as the probe, `chmod +x` and the hash check), and check the package registry's answer before offering it as the short route.
- **The session may refuse the download.** Give the person the exact command to run; continue from the file after the hash check.
- **Probe the main checkout as well as a worktree.** A migration that names live tasks, or a retired key still in use by one, shows in the dry run of the checkout whose tasks are live.
- **A tracked file the newer sync wrote can be refused by the older binary** with a message that it is "not a copy this spoolway knows". `sync --replace` takes the shipped copy and keeps values, and can write machine-only values into the tracked file; read `git diff` afterwards.

## Mapping

- **`sync --dry-run` lists files, not what it drops from them.** A real sync rewrote a project's own comments out of `config.toml` and reordered keys. Put the check in the draft: after the person's sync, `git diff` of the config shows no comment lost and no value changed, and the comments go back by hand. Never `git checkout --` the file: that throws away the keys the release added.
- **Some synced files are machine-local.** Skills a sync refreshes can sit under a path `.git/info/exclude` ignores. They change on disk and never reach a pull request: `git check-ignore -v <path>` before a draft lists one as a change.
- **A new config key can be tracked or machine-only.** The checkout's machine-only gate decides; run it on a throwaway copy of the config with the new keys and see whether it stays green.
- **A live task can fail `pipeline check` on its own.** A task whose `blocked_from` or stage names a step the pipeline no longer has fails the check and makes a reload refuse. Compare the As-Is run: when both fail alike, it is pre-existing, and the person resolves the task.
- **The binary's own check is the verdict for prompts.** A release can fail a prompt that names a command a lane is refused, even to forbid it. A search of the text hints; `pipeline check` settles. Describe the action in words in the rewritten prompt.
- **A suite that stubs a binary's `--help` passes while the real binary refuses.** Where a script builds commands from help text, compare the test's fixture with `<dir>/bin/spoolway <command> --help`, and regenerate the fixture from the binary.
- **Every pin of the As-Is must move together.** A CI job, a script or a doc that installs or names the As-Is makes the older binary read a config the newer sync wrote. Search for the As-Is version string and the installer names.
- **Queued task documents live outside git.** They sit in the project's home and carry keys. Match their keys with `spoolway task contract` (`refused`, `ignored`) before a release that retires one.

## Drafting and queueing

- **A merged pull request can leave its `task/<id>` branch on origin.** A release can refuse a task whose branch origin still holds. Take a fresh id and `setup.sh fresh-id <id>` right before the queue add.
- **`requires:` is not enforced.** It reaches the pull request as a note. Queue the dependent task after what it waits on has merged.
- **A retake leaves the installed plugin behind the lock, or the lock behind the install.** The user-scope install is shared by every worktree, so the pin-drift hook denies writes to the protected path in each of them until `claude plugin update spoolway-companion@spoolway-companion --scope user` runs and Claude Code restarts (or the types are retaken at the installed revision). Put both in the task's pause as the person's steps.
- **A draft's criteria can name a file git ignores.** Run `git check-ignore -v <path>` before a criterion lists it, or the review asks where the file went.

## After the install

- **A running process keeps the binary and the pipelines it loaded.** Restart the dispatcher after the install; after a merge `spoolway dispatch reload` brings the pipelines in, and it refuses, naming the task and step, while a task sits on a step the new files lack. Resume or unqueue that task rather than restart to force it.
- **`resume --stage` writes.** `resume --stage done` closes a blocked or paused task and skips its steps. Reading state is `queue list`, `queue show`, `queue route`, `lane` and `eval`.
- **A default editor that is not installed leaves swap files.** `doctor` notes it. Stale swap files in the queue directory are the trace of a command that opened one; set `$VISUAL` or `$EDITOR` first.
