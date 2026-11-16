#!/usr/bin/env bash
# Drives claude-plugin/hooks/pin-drift with fixture settings, fixture
# installed_plugins.json records and a stub `claude` CLI.
# Usage: tests/pin-drift.test.sh

set -u

repo="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo/claude-plugin/hooks/pin-drift"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

WIKI_SHA=7c94c9bf2968f17deb496b285db0afdb610a01d9
KT_SHA=6d82bbc6b8dc4e68e243add65576aae977229766
OTHER_SHA=1111111111111111111111111111111111111111

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; failures=$((failures + 1)); }

# Fresh project + config dir, pinning both entries.
setup() {
  project="$work/$1/project"
  config="$work/$1/config"
  bin="$work/$1/bin"
  mkdir -p "$project/.claude" "$project/.spoolway" "$config/plugins" "$bin"
  printf 'PIN_DRIFT_PROTECTED=.wiki/\n' >"$project/.spoolway/companion.env"
  cat >"$project/.claude/settings.json" <<EOF
{
  "enabledPlugins": {"alpha@example-market": true, "beta@example-market": true},
  "extraKnownMarketplaces": {
    "example-market": {"source": {"source": "settings", "name": "example-market", "plugins": [
      {"name": "alpha", "source": {"source": "git-subdir", "url": "https://example.com/alpha.git", "path": "claude-plugin", "ref": "v0.24.4", "sha": "$WIKI_SHA"}},
      {"name": "beta", "source": {"source": "git-subdir", "url": "https://example.com/beta.git", "path": "claude-plugin", "sha": "$KT_SHA"}}
    ]}}
  }
}
EOF
  # Stub CLI: fails unless a plugin list fixture exists.
  cat >"$bin/claude" <<EOF
#!/usr/bin/env bash
[ -f "$work/$1/list.json" ] && cat "$work/$1/list.json" && exit 0
exit 1
EOF
  chmod +x "$bin/claude"
}

installed() { # installed <wiki sha|null> <kt sha|null> [extra jq filter]
  jq -n --arg dir "$project" --argjson w "$1" --argjson k "$2" '
    {version: 2, plugins: {
      "alpha@example-market": [{scope: "project", projectPath: $dir, version: "0.24.4", lastUpdated: "2026-09-11T00:00:00Z", gitCommitSha: $w}],
      "beta@example-market": [{scope: "project", projectPath: $dir, version: "6d82bbc6b8dc-afc78acc", lastUpdated: "2026-09-11T00:00:00Z", gitCommitSha: $k}]
    }}' | jq "${3:-.}" >"$config/plugins/installed_plugins.json"
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

# 1. Matching pins: nothing to say, nothing denied.
setup match
installed "\"$WIKI_SHA\"" "\"$KT_SHA\""
run session-start; expect_silent "match: session start is silent"
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"; expect_silent "match: Write under .wiki/ passes"

# 2. Drift: the declared wiki sha moved, the install did not.
setup drift
installed "\"$OTHER_SHA\"" "\"$KT_SHA\""
run session-start
expect_jq "drift: systemMessage carries the exact update command" \
  '.systemMessage | contains("claude plugin update alpha@example-market --scope project") and contains("restart Claude Code")'
expect_jq "drift: systemMessage names only the drifting entry" '.systemMessage | contains("beta@example-market") | not'
expect_jq "drift: additionalContext tells the agent to keep out of .wiki/" \
  '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | contains("Do not write into .wiki/"))'
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"; denied "drift: Write under .wiki/ is denied"
run pre-tool-use "$(write_input Edit ".wiki/index.md")"; denied "drift: Edit of a relative .wiki/ path is denied"
expect_jq "drift: deny reason carries the update command" '.hookSpecificOutput.permissionDecisionReason | contains("claude plugin update alpha@example-market --scope project")'
run pre-tool-use "$(write_input Write "$project/src/app.ts")"; expect_silent "drift: Write outside .wiki/ passes"
run pre-tool-use "$(write_input Edit "$project/WIKI.md")"; expect_silent "drift: Edit of WIKI.md passes"
run pre-tool-use "$(write_input Write "$project/wiki/a.md")"; expect_silent "drift: Write under wiki/ (no dot) passes"

# 3. Update lifts the gate: the record now carries the pinned sha.
installed "\"$WIKI_SHA\"" "\"$KT_SHA\""
run session-start; expect_silent "after update: session start is silent"
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"; expect_silent "after update: Write under .wiki/ passes"

# 4. Fallback: installed_plugins.json absent, plugin list --json decides.
setup fallback
jq -n --arg dir "$project" '[
  {id: "alpha@example-market", version: "0.24.4", scope: "project", enabled: true, projectPath: $dir},
  {id: "beta@example-market", version: "6d82bbc6b8dc-afc78acc", scope: "project", enabled: true, projectPath: $dir}
]' >"$work/fallback/list.json"
run session-start; expect_silent "fallback (file absent): version vs ref and sha-shaped version match"
jq '(.[] | select(.id == "beta@example-market") | .version) = "111111111111-afc78acc"' "$work/fallback/list.json" >"$work/fallback/l" && mv "$work/fallback/l" "$work/fallback/list.json"
run session-start
expect_jq "fallback (file absent): sha-shaped version drift is reported with its method" \
  '.systemMessage | contains("claude plugin update beta@example-market --scope project") and contains("by version")'

# 5. Fallback: gitCommitSha null in the record.
setup nullsha
installed null "\"$KT_SHA\""
jq -n --arg dir "$project" '[{id: "alpha@example-market", version: "0.24.3", scope: "project", enabled: true, projectPath: $dir}]' >"$work/nullsha/list.json"
run session-start
expect_jq "fallback (null gitCommitSha): version 0.24.3 vs ref v0.24.4 is drift" \
  '.systemMessage | contains("claude plugin update alpha@example-market --scope project") and contains("by version vs ref")'

# 6. Neither source decides.
setup undecided
installed null null
run session-start
expect_jq "undecided: the hook says it cannot decide" '(.systemMessage | contains("cannot decide")) and .hookSpecificOutput == null'
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"; expect_silent "undecided: writes under .wiki/ are not denied"
printf '[]' >"$work/undecided/list.json"
run session-start
expect_jq "undecided: a record without gitCommitSha is not reported as missing" \
  '(.systemMessage | contains("record without gitCommitSha")) and (.systemMessage | contains("plugin install") | not)'

# 7. Not installed at all.
setup missing
printf '[]' >"$work/missing/list.json"
run session-start
expect_jq "missing: systemMessage carries the install command" '.systemMessage | contains("claude plugin install alpha@example-market --scope project")'
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"; denied "missing: Write under .wiki/ is denied"

# 8. settings.local.json disables the entry: its drift is not reported.
setup local
installed "\"$OTHER_SHA\"" "\"$KT_SHA\""
printf '{"enabledPlugins": {"alpha@example-market": false}}' >"$project/.claude/settings.local.json"
run session-start; expect_silent "local overlay: a disabled entry is skipped"

# 9. Several records: this project's own record wins over a newer one elsewhere.
setup records
installed "\"$WIKI_SHA\"" "\"$KT_SHA\"" \
  '.plugins["alpha@example-market"] += [{scope: "project", projectPath: "/elsewhere", lastUpdated: "2026-09-12T00:00:00Z", gitCommitSha: "'"$OTHER_SHA"'"}]'
run session-start; expect_silent "records: own projectPath record wins"
installed "\"$WIKI_SHA\"" "\"$KT_SHA\"" \
  '.plugins["alpha@example-market"] = [{scope: "project", projectPath: "/a", lastUpdated: "2026-09-10T00:00:00Z", gitCommitSha: "'"$WIKI_SHA"'"}, {scope: "project", projectPath: "/b", lastUpdated: "2026-09-12T00:00:00Z", gitCommitSha: "'"$OTHER_SHA"'"}]'
run session-start; expect_jq "records: without an own record, the newest one decides" '.systemMessage | contains("alpha@example-market")'

# 9b. Drift behind a record of another path only: install, never update.
setup foreign
installed "\"$WIKI_SHA\"" "\"$KT_SHA\"" \
  '.plugins["alpha@example-market"] = [{scope: "project", projectPath: "/elsewhere", lastUpdated: "2026-09-12T00:00:00Z", gitCommitSha: "'"$OTHER_SHA"'"}]'
run session-start
expect_jq "foreign record: systemMessage proposes install, never update" \
  '.systemMessage | contains("claude plugin install alpha@example-market --scope project") and (contains("plugin update") | not)'
expect_jq "foreign record: additionalContext proposes install, never update" \
  '.hookSpecificOutput.additionalContext | contains("claude plugin install alpha@example-market --scope project") and (contains("plugin update") | not)'
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"; denied "foreign record: Write under .wiki/ is denied"
expect_jq "foreign record: deny reason proposes install, never update" \
  '.hookSpecificOutput.permissionDecisionReason | contains("claude plugin install alpha@example-market --scope project") and (contains("plugin update") | not)'

# 9c. Own record behind the pin: update, in both outputs.
setup own
installed "\"$OTHER_SHA\"" "\"$KT_SHA\"" \
  '.plugins["alpha@example-market"] += [{scope: "project", projectPath: "/elsewhere", lastUpdated: "2026-09-12T00:00:00Z", gitCommitSha: "'"$WIKI_SHA"'"}]'
run session-start
expect_jq "own record: systemMessage proposes update, never install" \
  '.systemMessage | contains("claude plugin update alpha@example-market --scope project") and (contains("plugin install") | not)'
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"
expect_jq "own record: deny reason proposes update, never install" \
  '.hookSpecificOutput.permissionDecisionReason | contains("claude plugin update alpha@example-market --scope project") and (contains("plugin install") | not)'

# 9d. No protected path: drift is reported, nothing is denied.
setup unprotected
rm "$project/.spoolway/companion.env"
installed "\"$OTHER_SHA\"" "\"$KT_SHA\""
run session-start
expect_jq "unprotected: systemMessage still carries the update command" '.systemMessage | contains("claude plugin update alpha@example-market --scope project")'
expect_jq "unprotected: additionalContext names no protected path" '.hookSpecificOutput.additionalContext | contains("Do not write into") | not'
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"; expect_silent "unprotected: Write under .wiki/ passes"

# 9e. The environment wins over companion.env.
setup envwins
installed "\"$OTHER_SHA\"" "\"$KT_SHA\""
out="$(write_input Write "$project/pages/a.md" | PATH="$bin:$PATH" PIN_DRIFT_PROTECTED=pages CLAUDE_PROJECT_DIR="$project" CLAUDE_CONFIG_DIR="$config" bash "$hook" pre-tool-use)"; status=$?
denied "env wins: Write under the environment's path is denied"
out="$(write_input Write "$project/.wiki/a.md" | PATH="$bin:$PATH" PIN_DRIFT_PROTECTED=pages CLAUDE_PROJECT_DIR="$project" CLAUDE_CONFIG_DIR="$config" bash "$hook" pre-tool-use)"; status=$?
expect_silent "env wins: Write under the file's path passes"

# 9f. SPOOLWAY_COMPANION_WIKI_PIN_DRIFT_BLOCK=false: drift warns under the protected path, never denies.
setup warn
installed "\"$OTHER_SHA\"" "\"$KT_SHA\""
export SPOOLWAY_COMPANION_WIKI_PIN_DRIFT_BLOCK=false
run session-start
expect_jq "warn: systemMessage keeps the update command and says writes are allowed" \
  '.systemMessage | contains("claude plugin update alpha@example-market --scope project") and contains("are allowed despite the drift")'
expect_jq "warn: additionalContext does not say writes are denied" \
  '.hookSpecificOutput.additionalContext | (contains("are denied") | not) and contains("are allowed")'
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"
expect_jq "warn: Write under the protected path is warned, not denied" \
  '(.hookSpecificOutput.permissionDecision == null) and (.systemMessage | contains("claude plugin update alpha@example-market --scope project"))'
run pre-tool-use "$(write_input Write "$project/src/app.ts")"; expect_silent "warn: Write outside the protected path stays silent"
installed "\"$WIKI_SHA\"" "\"$KT_SHA\""
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"; expect_silent "warn: no drift, no warning"
export SPOOLWAY_COMPANION_WIKI_PIN_DRIFT_BLOCK=true
installed "\"$OTHER_SHA\"" "\"$KT_SHA\""
run pre-tool-use "$(write_input Write "$project/.wiki/concepts/a.md")"; denied "block=true: Write under the protected path is denied"
unset SPOOLWAY_COMPANION_WIKI_PIN_DRIFT_BLOCK

# 10. Never blocks: broken inputs still exit 0.
setup broken
printf '{not json' >"$project/.claude/settings.json"
printf '{not json' >"$config/plugins/installed_plugins.json"
run session-start; expect_silent "broken settings: exit 0, silent"
run pre-tool-use 'garbage'; expect_silent "garbage stdin: exit 0, silent"
run nonsense; expect_silent "unknown mode: exit 0, silent"

printf '\n%d failure(s)\n' "$failures"
[ "$failures" = 0 ]
