#!/usr/bin/env bash
# Written once by /spoolway-companion:setup's template, then yours: this repository owns it.
#
# SessionStart hook: tells the person, and the agent, that a plugin this project enables is not
# installed on this machine, with the user-scope commands that install it. A plugin the project
# enables with `enabledPlugins` in `.claude/settings.json` (a false in `.claude/settings.local.json`
# turns it off) is required; it is installed when the user's `installed_plugins.json` holds a
# record of it. Nothing is installed and nothing is written: the install is the person's, once per
# machine, because a plugin that is missing cannot ship the hook that reports it, so this one
# lives in the repository.
#
# Register it in `.claude/settings.json`:
#
#   "hooks": {"SessionStart": [{"matcher": "startup|resume|clear|compact",
#     "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/missing-plugin.sh\""}]}]}
#
# The hook never blocks the session: every path exits 0.

set -u

input="$(cat 2>/dev/null || true)"

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"systemMessage":"missing-plugin: jq is not installed, so the required plugins cannot be checked."}'
  exit 0
fi

project_dir="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)}"
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings="$project_dir/.claude/settings.json"
local_settings="$project_dir/.claude/settings.local.json"
installed_file="$config_dir/plugins/installed_plugins.json"

[ -f "$settings" ] || exit 0

overlay='{}'
if [ -f "$local_settings" ]; then
  overlay="$(jq -c '.enabledPlugins // {}' "$local_settings" 2>/dev/null)" || overlay='{}'
fi

# The enabled ids, one per line.
required="$(jq -r --argjson local "$overlay" '
  ((.enabledPlugins // {}) + $local) | to_entries[] | select(.value == true) | .key' "$settings" 2>/dev/null)" || exit 0
[ -n "$required" ] || exit 0

lines="" commands="" added=""
while IFS= read -r id; do
  [ -n "$id" ] || continue
  if [ -f "$installed_file" ] && jq -e --arg id "$id" --arg dir "$project_dir" \
    '(.plugins[$id] // []) | any(.scope == "user" or .projectPath == $dir)' "$installed_file" >/dev/null 2>&1; then
    continue
  fi
  market="${id#*@}"
  repo="$(jq -r --arg m "$market" '.extraKnownMarketplaces[$m].source | select(.source == "github") | .repo // empty' "$settings" 2>/dev/null)"
  lines+="- ${id}: not installed."$'\n'
  if [ -n "$repo" ] && [[ "$added" != *" $market "* ]]; then
    commands+="claude plugin marketplace add ${repo} --scope user"$'\n'
    added+=" $market "
  fi
  commands+="claude plugin install ${id} --scope user"$'\n'
done <<<"$required"

[ -n "$lines" ] || exit 0

message="This project needs plugins that are not installed on this machine:"$'\n'"${lines}Run once, then restart Claude Code:"$'\n'"${commands}"
jq -n --arg message "${message%$'\n'}" '
  {systemMessage: $message,
   hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $message}}'
exit 0
