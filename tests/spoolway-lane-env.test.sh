#!/usr/bin/env bash
# Offline test for the lane environment: lib.sh's lane_env/require_scratch/task_scratch, the
# shipped lane-env.sh and the plugin's lane-env SessionStart hook. A lane resumed after a
# dispatcher restart, a reboot or a usage-limit stop has no SPOOLWAY_TASK and no
# SPOOLWAY_SCRATCH; the resolver infers them from the worktree path, and an empty scratch space
# fails loudly instead of resolving to `/`.
# Usage: tests/spoolway-lane-env.test.sh (needs bash, git and jq)

set -u
# Nothing from the caller's environment: the checks step runs this suite inside a task.
unset "${!SPOOLWAY_@}"

repo="$(cd "$(dirname "$0")/.." && pwd)"
lib="$repo/claude-plugin/spoolway/types/scripts/spoolway/lib.sh"
lane_env_sh="$repo/claude-plugin/spoolway/types/scripts/spoolway/lane-env.sh"
hook="$repo/claude-plugin/hooks/lane-env"
plugin="$repo/claude-plugin"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1" "${3:-}"; fi; }

# --- A project home with a lane worktree, as spoolway cuts one --------------------------------

home="$work/home"
id=t1
mkdir -p "$home/queue" "$home/scratch/$id" "$home/worktrees/task-$id" "$work/main"
printf 'id = "x"\nroot = "%s"\n' "$work/main" > "$home/project.toml"
printf -- '---\nid: %s\nstage: implement\n---\n' "$id" > "$home/queue/$id.md"
git -C "$home/worktrees/task-$id" init -q -b "task/$id"
git -C "$home/worktrees/task-$id" commit -q --allow-empty -m init
wt="$home/worktrees/task-$id"

# run_lib <dir> <snippet>: source the shipped lib.sh with no SPOOLWAY_* set and run the snippet,
# which reads the directory as $dir.
run_lib() {
  local dir=$1 snippet=$2
  ( unset "${!SPOOLWAY_@}"; . "$lib"; eval "$snippet" ) > "$work/out" 2> "$work/err"
  rc=$?
}

# --- lib.sh: the resolver ---------------------------------------------------------------------

run_lib "$wt" 'lane_env "$dir"'
check "lane_env infers the task id" 'grep -qxF "export SPOOLWAY_TASK=t1" "$work/out"' "rc=$rc $(cat "$work/out" "$work/err")"
check "lane_env infers the task file" 'grep -qxF "export SPOOLWAY_TASK_FILE=$home/queue/t1.md" "$work/out"'
check "lane_env infers the scratch space" 'grep -qxF "export SPOOLWAY_SCRATCH=$home/scratch/t1" "$work/out"'
check "lane_env infers the worktree" 'grep -qxF "export SPOOLWAY_WORKTREE=$wt" "$work/out"'
check "lane_env infers the project root from project.toml" 'grep -qxF "export SPOOLWAY_REPO=$work/main" "$work/out"'

run_lib "$work/main" 'lane_env "$dir"'
check "lane_env fails outside a lane worktree" '[ $rc -ne 0 ] && [ ! -s "$work/out" ]' "rc=$rc $(cat "$work/out" "$work/err")"

run_lib "$wt" 'SPOOLWAY_TASK=kept; lane_env "$dir"'
check "lane_env keeps a value already set" 'grep -qxF "export SPOOLWAY_TASK=kept" "$work/out"'

run_lib "$wt" 'lane_scratch "$dir"'
check "lane_scratch prints the scratch space" '[ "$(cat "$work/out")" = "$home/scratch/t1" ]' "rc=$rc $(cat "$work/out" "$work/err")"

run_lib "$wt" 'lane_id "$dir"'
check "lane_id prints the task id" '[ "$(cat "$work/out")" = "t1" ]'

run_lib "$wt" 'lane_task_file "$dir"'
check "lane_task_file prints the task file" '[ "$(cat "$work/out")" = "$home/queue/t1.md" ]'

# --- lib.sh: the guard ------------------------------------------------------------------------

run_lib "$wt" 'require_scratch'
check "require_scratch fails loudly on an empty value" '[ $rc -ne 0 ] && grep -q "SPOOLWAY_SCRATCH is empty" "$work/err"' "rc=$rc $(cat "$work/err")"

run_lib "$wt" 'SPOOLWAY_SCRATCH=/tmp/s require_scratch'
check "require_scratch prints the value when set" '[ "$(cat "$work/out")" = "/tmp/s" ]'

run_lib "$wt" 'task_scratch ""'
check "task_scratch fails loudly when neither names a scratch space" '[ $rc -ne 0 ] && grep -q "no task file" "$work/err"' "rc=$rc $(cat "$work/err")"

run_lib "$wt" 'task_scratch "$home/queue/t1.md"'
check "task_scratch derives from the task file" '[ "$(cat "$work/out")" = "$home/scratch/t1" ]'

# --- lane-env.sh: sourced and executed --------------------------------------------------------

( cd "$wt" && unset "${!SPOOLWAY_@}"; . "$lane_env_sh" && printf '%s\n%s\n' "$SPOOLWAY_TASK" "$SPOOLWAY_SCRATCH" ) > "$work/out" 2> "$work/err"
check "sourced lane-env.sh sets the variables" '[ "$(sed -n 1p "$work/out")" = "t1" ] && [ "$(sed -n 2p "$work/out")" = "$home/scratch/t1" ]' "rc=$? $(cat "$work/out" "$work/err")"

( cd "$work/main" && unset "${!SPOOLWAY_@}"; . "$lane_env_sh" ) > "$work/out" 2> "$work/err"
rc=$?
check "sourced lane-env.sh fails loudly outside a lane worktree" '[ "$rc" -ne 0 ]' "rc=$rc $(cat "$work/err")"

( cd "$wt" && unset "${!SPOOLWAY_@}"; bash "$lane_env_sh" scratch ) > "$work/out" 2> "$work/err"
check "executed lane-env.sh scratch prints the scratch space" '[ "$(cat "$work/out")" = "$home/scratch/t1" ]' "rc=$? $(cat "$work/out" "$work/err")"

( cd "$wt" && unset "${!SPOOLWAY_@}"; bash "$lane_env_sh" ) > "$work/out" 2> "$work/err"
check "executed lane-env.sh prints the exports" 'grep -qxF "export SPOOLWAY_TASK=t1" "$work/out"' "rc=$? $(cat "$work/out" "$work/err")"

# --- the SessionStart hook --------------------------------------------------------------------

envfile="$work/env"
rm -f "$envfile"
printf '{"session_id":"t","cwd":"%s","hook_event_name":"SessionStart","source":"resume"}' "$wt" \
  | CLAUDE_PLUGIN_ROOT="$plugin" CLAUDE_ENV_FILE="$envfile" bash "$hook" > "$work/out" 2> "$work/err"
rc=$?
check "the hook exits 0 in a lane worktree" '[ "$rc" -eq 0 ]' "rc=$rc $(cat "$work/err")"
check "the hook writes the task id to CLAUDE_ENV_FILE" 'grep -qxF "export SPOOLWAY_TASK=t1" "$envfile"' "$(cat "$envfile" 2>/dev/null)"
check "the hook writes the scratch space to CLAUDE_ENV_FILE" 'grep -qxF "export SPOOLWAY_SCRATCH=$home/scratch/t1" "$envfile"'
check "the hook prints nothing on stdout" '[ ! -s "$work/out" ]' "$(cat "$work/out")"

rm -f "$envfile"
printf '{"session_id":"t","cwd":"%s","hook_event_name":"SessionStart"}' "$work/main" \
  | CLAUDE_PLUGIN_ROOT="$plugin" CLAUDE_ENV_FILE="$envfile" bash "$hook" > "$work/out" 2> "$work/err"
rc=$?
check "the hook does nothing outside a lane worktree" '[ "$rc" -eq 0 ] && [ ! -e "$envfile" ]' "rc=$rc $(cat "$work/err")"

# --- the prompts carry the preamble -----------------------------------------------------------

for p in "$repo"/claude-plugin/spoolway/types/setup/prompts/*/PROMPT.md; do
  [ -L "$(dirname "$p")" ] && continue
  if grep -qF '. scripts/spoolway/lane-env.sh || exit 1' "$p"; then
    pass "the prompt $(basename "$(dirname "$p")") names the lane-environment guard"
  else
    fail "the prompt $(basename "$(dirname "$p")") names the lane-environment guard"
  fi
done

[ "$failures" -eq 0 ] && printf 'all ok\n'
exit "$([ "$failures" -eq 0 ] && echo 0 || echo 1)"
