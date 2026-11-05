# Contributing

Contributions are licensed under the MIT licence of this repository, the same licence the
repository is offered under (inbound = outbound). By opening a pull request you agree that your
contribution is offered under it.

## Content rule

The companion is generic. It carries:

- no domain knowledge of any project that consumes it: no doctrine, glossary or rules of a
  product, and no product name;
- no pages of a knowledge base (wiki or otherwise): a consumer keeps its own;
- no quoted third-party text: a dependency is named and linked, never copied in.

A behaviour one consumer needs goes behind an extension point (see the README), not into the
pipelines, prompts or scripts.

## Changes

- Commit messages and pull request titles follow Conventional Commits:
  `type(scope): lowercase sentence`.
- No AI attribution in a commit, comment or file: no generated-by footer, no tool or model named as
  an author or co-author.
- A change under `claude-plugin/spoolway/types/` regenerates `claude-plugin/spoolway/types.manifest`
  (`bash claude-plugin/spoolway/types.sh manifest > claude-plugin/spoolway/types.manifest`).
- Run every test before you open a pull request: `for t in tests/*.test.sh; do bash "$t"; done`.
