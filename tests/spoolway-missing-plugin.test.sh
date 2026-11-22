#!/usr/bin/env bash
# Drives the consumer-owned SessionStart hook template claude-plugin/templates/claude/hooks/
# missing-plugin.sh offline: fixture settings and fixture installed_plugins.json records, no claude.
# Also holds this repository to the catalogue model: its catalogue is named spoolway-companion, and
# its own settings declare no inline marketplace and no plugin list.
# Usage: tests/spoolway-missing-plugin.test.sh (needs bash and jq)

set -u

repo="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo/claude-plugin/templates/claude/hooks/missing-plugin.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1" "${3:-}"; fi; }

# --- This repository is the catalogue -------------------------------------------------------

check "the catalogue is named spoolway-companion and lists the one plugin" \
  '[ "$(jq -r .name "$repo/.claude-plugin/marketplace.json")" = spoolway-companion ] && [ "$(jq -r "[.plugins[].name] | join(\",\")" "$repo/.claude-plugin/marketplace.json")" = spoolway-companion ]'
check "this repository's settings hold the github pointer and the id, no inline marketplace, no plugin list, no sha" \
  '[ "$(jq -r ".extraKnownMarketplaces[\"spoolway-companion\"].source | [.source, .repo] | join(\" \")" "$repo/.claude/settings.json")" = "github theTestTube/spoolway-companion" ] && ! grep -qE "\"(sha|plugins)\"|\"settings\"" "$repo/.claude/settings.json" && jq -e ".enabledPlugins[\"spoolway-companion@spoolway-companion\"]" "$repo/.claude/settings.json" > /dev/null'
check "no tracked file but the tests declares an inline marketplace" \
  '[ -z "$(cd "$repo" && git grep -lE "\"source\": *\"settings\"" -- . ":!tests" ":!README.md" ":!docs")" ]'

# --- The hook -------------------------------------------------------------------------------

[ -x "$hook" ] || fail "the template is executable"

fixture() { # fixture <name> <settings json>: a project and a config dir
  project="$work/$1/project"; config="$work/$1/config"
  mkdir -p "$project/.claude" "$config/plugins"
  printf '%s\n' "$2" > "$project/.claude/settings.json"
}
installed() { printf '%s\n' "$1" > "$config/plugins/installed_plugins.json"; }
run() { out=$(printf '{"cwd":"%s"}' "$project" | CLAUDE_PROJECT_DIR="$project" CLAUDE_CONFIG_DIR="$config" bash "$hook" 2>&1); status=$?; }

SETTINGS='{"enabledPlugins": {"spoolway-companion@spoolway-companion": true, "wiki@llm-wiki": true, "off@m": false},
  "extraKnownMarketplaces": {"spoolway-companion": {"source": {"source": "github", "repo": "theTestTube/spoolway-companion"}},
                              "llm-wiki": {"source": {"source": "github", "repo": "acme/llm-wiki"}}}}'

fixture none "$SETTINGS"
installed '{"version": 2, "plugins": {}}'
run
check "nothing installed: both required plugins are named, with the user-scope commands" \
  '[ $status -eq 0 ] && jq -e ".systemMessage | contains(\"spoolway-companion@spoolway-companion: not installed\") and contains(\"wiki@llm-wiki: not installed\") and contains(\"claude plugin marketplace add theTestTube/spoolway-companion --scope user\") and contains(\"claude plugin install spoolway-companion@spoolway-companion --scope user\") and contains(\"claude plugin marketplace add acme/llm-wiki --scope user\") and contains(\"restart Claude Code\")" <<<"$out" > /dev/null' "$out"
check "a plugin the project disables is not required" '! grep -q "off@m" <<<"$out"'
check "the agent is told too" 'jq -e ".hookSpecificOutput | .hookEventName == \"SessionStart\" and (.additionalContext | contains(\"not installed\"))" <<<"$out" > /dev/null' "$out"
check "it never proposes the project scope" '! grep -q -- "--scope project" <<<"$out"'

installed '{"version": 2, "plugins": {"spoolway-companion@spoolway-companion": [{"scope": "user", "installPath": "/x", "gitCommitSha": "abc"}]}}'
run
check "one installed at user scope: only the other is named" \
  '[ $status -eq 0 ] && jq -e ".systemMessage | contains(\"wiki@llm-wiki: not installed\") and (contains(\"spoolway-companion@spoolway-companion: not installed\") | not) and (contains(\"theTestTube/spoolway-companion\") | not)" <<<"$out" > /dev/null' "$out"

installed '{"version": 2, "plugins": {"spoolway-companion@spoolway-companion": [{"scope": "user"}], "wiki@llm-wiki": [{"scope": "project", "projectPath": "'"$project"'"}]}}'
run
check "every required plugin installed (a project record of this project counts): silent" '[ $status -eq 0 ] && [ -z "$out" ]' "$out"

installed '{"version": 2, "plugins": {"spoolway-companion@spoolway-companion": [{"scope": "user"}], "wiki@llm-wiki": [{"scope": "project", "projectPath": "/elsewhere"}]}}'
run
check "a project record of another path does not count" '[ $status -eq 0 ] && grep -q "wiki@llm-wiki: not installed" <<<"$out"' "$out"

printf '{"enabledPlugins": {"spoolway-companion@spoolway-companion": false, "wiki@llm-wiki": false}}\n' > "$project/.claude/settings.local.json"
run
check "settings.local.json turns a required plugin off" '[ $status -eq 0 ] && [ -z "$out" ]' "$out"
rm "$project/.claude/settings.local.json"

fixture nomarket '{"enabledPlugins": {"tool@official": true}}'
installed '{"version": 2, "plugins": {}}'
run
check "a marketplace the settings do not declare gets only the install command" \
  '[ $status -eq 0 ] && jq -e ".systemMessage | contains(\"claude plugin install tool@official --scope user\") and (contains(\"marketplace add\") | not)" <<<"$out" > /dev/null' "$out"

fixture nofile "$SETTINGS"
rm "$project/.claude/settings.json"
run
check "no settings.json: silent" '[ $status -eq 0 ] && [ -z "$out" ]' "$out"
fixture broken '{not json'
run
check "broken settings: exit 0, silent" '[ $status -eq 0 ] && [ -z "$out" ]' "$out"
fixture brokenrec "$SETTINGS"
installed '{not json'
run
check "broken install records: exit 0, the plugins are named" '[ $status -eq 0 ] && grep -q "not installed" <<<"$out"' "$out"

check "the template names no project of any consumer" '! grep -rniE "$(printf "\x69[- ]?\x63\x68\x69\x6e\x67")" "$hook"'

echo
[ $failures -eq 0 ] && echo "all passed" || echo "$failures failed"
[ $failures -eq 0 ]
