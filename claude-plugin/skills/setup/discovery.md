# Discovery rules

Reached from step 2b of "A spoolway update". `bash <base>/setup.sh discover`, from the checkout's root, applies every rule below and prints tab-separated lines. It writes nothing.

## Sources

A candidate is a checkout; each is reported with every source that found it, and listed once.

1. **The current checkout.**
2. **The machine's registry.** Every `~/.spoolway/*/project.toml` holds the project's recorded checkout root.
3. **`docs/agents/projects.md`.** Each repository of its table is looked up as a checkout beside this one (`../<name>`), the layout that file documents.

A checkout is the same one when its git common directory is: a worktree of a project counts as that project.

## What a candidate reports

A candidate that cannot be read prints `unreadable`, its sources and the reason (`checkout gone`, `not a git checkout`, `no .spoolway/ directory`, `no access`). It is named in the report and never dropped.

A readable one prints:

| Line | Holds |
|---|---|
| `consumer` | the path and its sources |
| `pin` | the companion revision in `.spoolway/plugin.lock`, or `none` |
| `pipeline` | each `.spoolway/pipelines/*.yml`: `companion` (its lock hash equals the hash in this revision's `types.manifest`), `companion, another revision` (it is locked and the hash differs) or `own` (the lock does not list it) |
| `prompt` | each directory under `.spoolway/prompts/` |
| `subset` | `.spoolway/types.subset`, present with its path count, or absent |
| `override` | each file in the project home's `overrides/` with its first three non-comment lines; `none found` when no registry project holds the checkout |
| `spoolway-pin` | each `file:line` of `.github`, `scripts`, `docs`, `README.md` and `CLAUDE.md` that names `spoolway` with a release number, and that number |
| `task` | each queued or blocked task of the project; `unreadable` when `queue list --json` fails or no project holds the checkout |

## Reading it

- A pin that differs from the current checkout's, or a `spoolway-pin` that differs from the As-Is, is a place the version change reaches.
- `own` pipelines are the consumer's: the companion's types do not cover them, so the gap's breaking changes meet them directly.
- An `unreadable` candidate stays unmapped until the person says why it is safe to leave.
