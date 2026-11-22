#!/usr/bin/env bash
# Drives claude-plugin/hooks/pin-drift offline against fixture consumers: a .spoolway/plugin.lock,
# fixture installed_plugins.json records and a stub `claude` CLI. No settings.json is read.
# Usage: tests/pin-drift.test.sh

set -u
# The machine's own switch must not change what the hook answers here.
unset SPOOLWAY_COMPANION_WIKI_PIN_DRIFT_BLOCK PIN_DRIFT_PROTECTED

repo="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo/claude-plugin/hooks/pin-drift"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

LOCK_SHA=6d82bbc6b8dc4e68e243add65576aae977229766
OTHER_SHA=1111111111111111111111111111111111111111
ID=spoolway-companion@spoolway-companion

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; failures=$((failures + 1)); }

# Fresh consumer + config dir: a lock at LOCK_SHA, and a settings.json whose inline entry names
# another sha, which the hook must never read.
setup() {
  project="$work/$1/project"
  config="$work/$1/config"
  bin="$work/$1/bin"
  mkdir -p "$project/.claude" "$project/.spoolway" "$config/plugins" "$bin"
  printf 'PIN_DRIFT_PROTECTED=.wiki/\n' >"$project/.spoolway/companion.env"
  printf '# Written by /spoolway-companion:spoolway-types\nplugin spoolway-companion\nrevision %s\n100644 abc\t.spoolway/pipelines/dev.yml\n' "$LOCK_SHA" >"$project/.spoolway/plugin.lock"
  cat >"$project/.claude/settings.json" <<JSON
{
  "enabledPlugins": {"$ID": true},
  "extraKnownMarketplaces": {
    "example-market": {"source": {"source": "settings", "name": "example-market", "plugins": [
      {"name": "spoolway-companion", "source": {"source": "git-subdir", "url": "https://example.com/x.git", "path": "claude-plugin", "sha": "$OTHER_SHA"}}
    ]}}
  }
}
JSON
  # Stub CLI: fails unless a plugin list fixture exists.
  cat >"$bin/claude" <<STUB
#!/usr/bin/env bash
[ -f "$work/$1/list.json" ] && cat "$work/$1/list.json" && exit 0
exit 1
STUB
  chmod +x "$bin/claude"
}

installed() { # installed <json sha|null> [extra jq filter]: a user-scope record, as Claude Code writes it
  jq -n --argjson s "$1" '
    {version: 2, plugins: {"spoolway-companion@spoolway-companion": [
      {scope: "user", installPath: "/cache/x", version: "6d82bbc6b8dc-afc78acc", lastUpdated: "2026-09-11T00:00:00Z", gitCommitSha: $s}]}}' \
    | jq "${2:-.}" >"$config/plugins/installed_plugins.json"
}

run() { # run <mode> [stdin json]
  local stdin="${2:-}"
  [ -n "$stdin" ] || stdin="{\"session_id\":\"t\",\"cwd\":\"$project\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}"
  out="$(printf '%s' "$stdin" | PATH="$bin:$PATH" CLAUDE_PROJECT_DIR="$project" CLAUDE_CONFIG_DIR="$config" bash "$hook" "$1")"
  status=$?
}

write_input() { # write_input <tool> <file_path>
  printf '{"session_id":"t","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"file_path":"%s","content":"x"}}' "$project" "$1" "$2"
}

expect_silent() { [ "$status" = 0 ] && [ -z "$out" ] && pass "$1" || fail "$1" "exit=$status out=$out"; }
expect_jq() { [ "$status" = 0 ] && jq -e "$2" <<<"$out" >/dev/null 2>&1 && pass "$1" || fail "$1" "exit=$status out=$out"; }
denied() { expect_jq "$1" '.hookSpecificOutput.permissionDecision == "deny"'; }

# 1. The install is the lock's revision: nothing to say, nothing denied.
setup match
installed "\"$LOCK_SHA\""
run session-start; expect_silent "match: session start is silent, whatever an inline entry says"
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"; expect_silent "match: Write under .wiki/ passes"

# 2. Drift: the lock moved (or the install did), the other did not.
setup drift
installed "\"$OTHER_SHA\""
run session-start
expect_jq "drift: systemMessage carries the user-scope update commands and the restart" \
  '.systemMessage | contains("claude plugin marketplace update spoolway-companion") and contains("claude plugin update spoolway-companion@spoolway-companion --scope user") and contains("restart Claude Code")'
expect_jq "drift: systemMessage names the installed and the locked revision, and the bump for an install that is ahead" \
  '.systemMessage | contains("installed 111111111111") and contains("plugin.lock holds 6d82bbc6b8dc") and contains("setup bump")'
expect_jq "drift: it never proposes the project scope" '.systemMessage | contains("--scope project") | not'
expect_jq "drift: additionalContext tells the agent to keep out of .wiki/" \
  '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | contains("Do not write into .wiki/"))'
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"; denied "drift: Write under .wiki/ is denied"
run pre-tool-use "$(write_input Edit ".wiki/index.md")"; denied "drift: Edit of a relative .wiki/ path is denied"
expect_jq "drift: deny reason carries the update command" '.hookSpecificOutput.permissionDecisionReason | contains("claude plugin update spoolway-companion@spoolway-companion --scope user")'
run pre-tool-use "$(write_input Write "$project/src/app.ts")"; expect_silent "drift: Write outside .wiki/ passes"
run pre-tool-use "$(write_input Write "$project/wiki/a.md")"; expect_silent "drift: Write under wiki/ (no dot) passes"

# 3. Update lifts the gate: the record now carries the locked revision.
installed "\"$LOCK_SHA\""
run session-start; expect_silent "after update: session start is silent"
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"; expect_silent "after update: Write under .wiki/ passes"

# 3b. settings.json is never read: an inline sha that disagrees changes nothing, and no file works too.
setup inline
installed "\"$LOCK_SHA\""
run session-start; expect_silent "inline sha: a settings.json that disagrees with the lock is not read"
rm "$project/.claude/settings.json"
run session-start; expect_silent "no settings.json: the lock and the record are enough"

# 4. No lock, or a lock of another plugin: nothing to compare.
setup nolock
installed "\"$OTHER_SHA\""
rm "$project/.spoolway/plugin.lock"
run session-start; expect_silent "no lock: silent, however far the install is"
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"; expect_silent "no lock: Write under .wiki/ passes"
printf 'plugin other-harness\nrevision %s\n' "$LOCK_SHA" >"$project/.spoolway/plugin.lock"
run session-start; expect_silent "another plugin's lock: silent"

# 5. Fallback: installed_plugins.json absent, plugin list --json decides by its sha-shaped version.
setup fallback
jq -n '[{id: "spoolway-companion@spoolway-companion", version: "6d82bbc6b8dc-afc78acc", scope: "user", enabled: true}]' >"$work/fallback/list.json"
run session-start; expect_silent "fallback (file absent): a sha-shaped version that matches the lock is silent"
jq '.[0].version = "111111111111-afc78acc"' "$work/fallback/list.json" >"$work/fallback/l" && mv "$work/fallback/l" "$work/fallback/list.json"
run session-start
expect_jq "fallback (file absent): a sha-shaped version that differs is drift, with its method" \
  '.systemMessage | contains("claude plugin update spoolway-companion@spoolway-companion --scope user") and contains("by version")'

# 5b. Fallback: gitCommitSha null in the record, and a version that is no commit.
setup nullsha
installed null
jq -n '[{id: "spoolway-companion@spoolway-companion", version: "0.24.3", scope: "user", enabled: true}]' >"$work/nullsha/list.json"
run session-start
expect_jq "fallback (null gitCommitSha): a version that is no commit cannot decide" \
  '(.systemMessage | contains("cannot decide")) and .hookSpecificOutput == null'

# 6. Neither source decides.
setup undecided
installed null
run session-start
expect_jq "undecided: the hook says it cannot decide" '(.systemMessage | contains("cannot decide")) and .hookSpecificOutput == null'
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"; expect_silent "undecided: writes under .wiki/ are not denied"

# 7. Several records: the user-scope one wins, then this project's own, then the newest.
setup records
installed "\"$LOCK_SHA\"" \
  '.plugins["spoolway-companion@spoolway-companion"] += [{scope: "project", projectPath: "/elsewhere", lastUpdated: "2026-09-12T00:00:00Z", gitCommitSha: "'"$OTHER_SHA"'"}]'
run session-start; expect_silent "records: the user-scope record wins over a newer project one"
installed "\"$LOCK_SHA\"" \
  '.plugins["spoolway-companion@spoolway-companion"] = [{scope: "project", projectPath: "'"$project"'", lastUpdated: "2026-09-10T00:00:00Z", gitCommitSha: "'"$LOCK_SHA"'"}, {scope: "project", projectPath: "/b", lastUpdated: "2026-09-12T00:00:00Z", gitCommitSha: "'"$OTHER_SHA"'"}]'
run session-start; expect_silent "records: without a user-scope record, this project's own wins"
installed "\"$LOCK_SHA\"" \
  '.plugins["spoolway-companion@spoolway-companion"] = [{scope: "project", projectPath: "/a", lastUpdated: "2026-09-10T00:00:00Z", gitCommitSha: "'"$LOCK_SHA"'"}, {scope: "project", projectPath: "/b", lastUpdated: "2026-09-12T00:00:00Z", gitCommitSha: "'"$OTHER_SHA"'"}]'
run session-start; expect_jq "records: without either, the newest one decides" '.systemMessage | contains("spoolway-companion@spoolway-companion")'

# 8. No protected path: drift is reported, nothing is denied.
setup unprotected
rm "$project/.spoolway/companion.env"
installed "\"$OTHER_SHA\""
run session-start
expect_jq "unprotected: systemMessage still carries the update command" '.systemMessage | contains("claude plugin update spoolway-companion@spoolway-companion --scope user")'
expect_jq "unprotected: additionalContext names no protected path" '.hookSpecificOutput.additionalContext | contains("Do not write into") | not'
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"; expect_silent "unprotected: Write under .wiki/ passes"

# 9. The environment wins over companion.env.
setup envwins
installed "\"$OTHER_SHA\""
out="$(write_input Write "$project/pages/a.md" | PATH="$bin:$PATH" PIN_DRIFT_PROTECTED=pages CLAUDE_PROJECT_DIR="$project" CLAUDE_CONFIG_DIR="$config" bash "$hook" pre-tool-use)"; status=$?
denied "env wins: Write under the environment's path is denied"
out="$(write_input Write "$project/.wiki/a.md" | PATH="$bin:$PATH" PIN_DRIFT_PROTECTED=pages CLAUDE_PROJECT_DIR="$project" CLAUDE_CONFIG_DIR="$config" bash "$hook" pre-tool-use)"; status=$?
expect_silent "env wins: Write under the file's path passes"

# 10. SPOOLWAY_COMPANION_WIKI_PIN_DRIFT_BLOCK=false: drift warns under the protected path, never denies.
setup warn
installed "\"$OTHER_SHA\""
export SPOOLWAY_COMPANION_WIKI_PIN_DRIFT_BLOCK=false
run session-start
expect_jq "warn: systemMessage keeps the update command and says writes are allowed" \
  '.systemMessage | contains("claude plugin update spoolway-companion@spoolway-companion --scope user") and contains("are allowed despite the drift")'
expect_jq "warn: additionalContext does not say writes are denied" \
  '.hookSpecificOutput.additionalContext | (contains("are denied") | not) and contains("are allowed")'
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"
expect_jq "warn: Write under the protected path is warned, not denied" \
  '(.hookSpecificOutput.permissionDecision == null) and (.systemMessage | contains("claude plugin update spoolway-companion@spoolway-companion --scope user"))'
run pre-tool-use "$(write_input Write "$project/src/app.ts")"; expect_silent "warn: Write outside the protected path stays silent"
installed "\"$LOCK_SHA\""
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"; expect_silent "warn: no drift, no warning"
export SPOOLWAY_COMPANION_WIKI_PIN_DRIFT_BLOCK=true
installed "\"$OTHER_SHA\""
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"; denied "block=true: Write under the protected path is denied"
unset SPOOLWAY_COMPANION_WIKI_PIN_DRIFT_BLOCK

# 11. Never blocks: broken inputs still exit 0.
setup broken
printf '{not json' >"$config/plugins/installed_plugins.json"
run session-start; expect_jq "broken install records: exit 0, the hook says it cannot decide" '(.systemMessage | contains("cannot decide")) and .hookSpecificOutput == null'
run pre-tool-use 'garbage'; expect_silent "garbage stdin: exit 0, silent"
run nonsense; expect_silent "unknown mode: exit 0, silent"

printf '\n%d failure(s)\n' "$failures"
[ "$failures" = 0 ]
