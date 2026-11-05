#!/usr/bin/env bash
# Offline test for the shipped `ci` step script: claude-plugin/spoolway/types/
# scripts/spoolway/ci.sh, driven against a fake `gh` that answers from files, in a repository made
# here. Nothing reaches GitHub or the network, and no dispatcher starts.
# Usage: tests/spoolway-ci.test.sh (needs bash, git and jq)

set -u

unset "${!SPOOLWAY_@}"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

repo="$(cd "$(dirname "$0")/.." && pwd)"
shipped="$repo/claude-plugin/spoolway/types/scripts/spoolway"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1" "${3:-}"; fi; }

app="$work/app"
mkdir -p "$app/scripts/spoolway" "$work/bin" "$work/state"
cp "$shipped/ci.sh" "$shipped/lib.sh" "$app/scripts/spoolway/"
git -C "$app" init -q -b main
git -C "$app" add -A 2> /dev/null
git -C "$app" commit -q --allow-empty -m init
git -C "$app" checkout -q -b task/demo

# Fake gh, run in the directory of the repository it is asked about ($PWD): `pr list` prints the
# url held in $PWD/.pr (nothing when absent), `pr checks` prints the JSON held in $PWD/.checks, `pr view` the head
# commit held in $PWD/.head (the repository's own HEAD when absent).
cat > "$work/bin/gh" <<'FAKE'
#!/bin/sh
echo "gh $* (in $PWD)" >> "$CALLS"
case "$1 $2" in
  "pr list") [ -f .pr ] && cat .pr ;;
  "pr checks") [ -f .checks ] && cat .checks; exit 0 ;;
  "pr view") if [ -f .head ]; then cat .head; else git rev-parse HEAD; fi ;;
esac
exit 0
FAKE
chmod +x "$work/bin/gh"
export CALLS="$work/calls"

task=$work/state/t1.md
make_task() {
  local stage=$1; shift
  { printf -- '---\nid: t1\nstage: %s\nbase: main\n' "$stage"
    [ $# -gt 0 ] && printf '%s\n' "$@"
    printf -- '---\n\nBody.\n'; } > "$task"
}
run() {
  (cd "$app" && PATH="$work/bin:$PATH" SPOOLWAY_TASK_FILE="$task" SPOOLWAY_TASK=t1 \
    CI_WAIT_SECONDS="${WAIT:-0}" CI_POLL_SECONDS=0 \
    bash scripts/spoolway/ci.sh "$@") > "$work/out" 2> "$work/err"
  rc=$?
}
reset() { rm -f "$app/.head" "$app/.pr" "$app/.checks" "$CALLS"; }

green='[{"name":"Gates","bucket":"pass","link":"https://ci/1"},{"name":"Lint","bucket":"skipping","link":"https://ci/2"}]'
red='[{"name":"Gates","bucket":"pass","link":"https://ci/1"},{"name":"Typecheck","bucket":"fail","link":"https://ci/run/42"}]'
running='[{"name":"Gates","bucket":"pass","link":"https://ci/1"},{"name":"E2E","bucket":"pending","link":"https://ci/run/77"}]'

# --- The app pull request ---------------------------------------------------------------------

reset; make_task ci
echo https://github.com/o/r/pull/5 > "$app/.pr"; echo "$green" > "$app/.checks"
run
check "all checks green passes" '[ $rc -eq 0 ] && grep -q "every check is green" "$work/out"' "rc=$rc $(cat "$work/out" "$work/err")"

echo "$red" > "$app/.checks"
run
check "a red check fails" '[ $rc -eq 1 ]' "rc=$rc"
check "the red check is named with its run URL" 'grep -q "Typecheck" "$work/err" && grep -q "https://ci/run/42" "$work/err"' "$(cat "$work/err")"
check "a passing check is not named as failing" '! grep -q "Gates" "$work/err"'

echo '[{"name":"Build","bucket":"cancel","link":"https://ci/run/9"}]' > "$app/.checks"
run
check "a cancelled check fails" '[ $rc -eq 1 ] && grep -q "https://ci/run/9" "$work/err"'

echo "$running" > "$app/.checks"
run
check "a check still running at the timeout fails" '[ $rc -eq 1 ]' "rc=$rc"
check "the message says unfinished, not red, and names the check and its URL" \
  'grep -q "unfinished, not red" "$work/err" && grep -q "E2E" "$work/err" && grep -q "https://ci/run/77" "$work/err"' "$(cat "$work/err")"

echo "$running" > "$app/.checks"
echo '[{"name":"Typecheck","bucket":"fail","link":"https://ci/run/42"},{"name":"E2E","bucket":"pending","link":"https://ci/run/77"}]' > "$app/.checks"
WAIT=60 run
check "a red check fails at once, without waiting for the unfinished ones" '[ $rc -eq 1 ] && grep -q "https://ci/run/42" "$work/err"'

echo '[]' > "$app/.checks"
run
check "no check at all fails, saying so" '[ $rc -eq 1 ] && grep -q "no check at all" "$work/err"' "rc=$rc $(cat "$work/err")"
rm "$app/.checks"
run
check "a gh that reports nothing fails the same way" '[ $rc -eq 1 ] && grep -q "no check at all" "$work/err"'

reset
echo "$green" > "$app/.checks"
run
check "no open pull request on the branch fails, saying so" '[ $rc -eq 1 ] && grep -q "no open pull request on task/demo" "$work/err"' "rc=$rc $(cat "$work/err")"
check "no matching pull request does not read any check" '! grep -q "pr checks" "$CALLS"'

# --- The head of the pull request ---------------------------------------------------------------

reset; make_task ci
old=$(git -C "$app" rev-parse HEAD~1 2> /dev/null || echo 0000000000000000000000000000000000000000)
echo https://github.com/o/r/pull/5 > "$app/.pr"; echo "$green" > "$app/.checks"; echo "$old" > "$app/.head"
run
check "green checks on an older head do not pass" '[ $rc -eq 1 ]' "rc=$rc $(cat "$work/out")"
check "the failure names both commits" 'grep -q "$old" "$work/err" && grep -q "$(git -C "$app" rev-parse HEAD)" "$work/err" && grep -q "never became" "$work/err"' "$(cat "$work/err")"
check "the older head's checks are not read" '! grep -q "pr checks" "$CALLS"'

# The fake catches up on the third look: the step waits, then passes.
cat > "$work/bin/catchup" <<'CU'
#!/bin/sh
n=$(cat "$STATE_N" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$STATE_N"
[ $n -ge 3 ] && rm -f .head
CU
mv "$work/bin/gh" "$work/bin/gh.real"
cat > "$work/bin/gh" <<'WRAP'
#!/bin/sh
case "$1 $2" in "pr view") "$(dirname "$0")/catchup" ;; esac
exec "$(dirname "$0")/gh.real" "$@"
WRAP
chmod +x "$work/bin/gh" "$work/bin/catchup"
export STATE_N="$work/n"; rm -f "$STATE_N"
WAIT=60 run
check "once the head is the worktree's commit with green checks it passes" '[ $rc -eq 0 ] && grep -q "every check is green" "$work/out"' "rc=$rc $(cat "$work/err")"
mv "$work/bin/gh.real" "$work/bin/gh"; rm -f "$work/bin/catchup"

# --- Guards -----------------------------------------------------------------------------------

make_task ci "skip_steps: [ci]"
run
check "skip_steps naming ci passes at once" '[ $rc -eq 0 ] && grep -q "passing at once" "$work/out"'
make_task checks
run
check "refuses to run on another step's stage" '[ $rc -eq 64 ]'
make_task ci
run --help
check "takes no argument" '[ $rc -eq 64 ]'

# --- A task that changed nothing here -------------------------------------------------------

# Its extra repositories' pull requests are the consumer's extra-* scripts' to watch; this
# repository opened none, so nothing is read here.
reset; make_task ci "starts_from: main"
run
check "a task that changed nothing in this repository passes at once" '[ $rc -eq 0 ] && grep -q "nothing changed in this repository" "$work/out" && [ ! -s "$CALLS" ]' "rc=$rc $(cat "$work/err" "$work/out")"
echo change > "$app/f"; git -C "$app" add f; git -C "$app" commit -q -m app
reset; make_task ci "starts_from: main"
run
check "a task that changed this repository and has no pull request fails" '[ $rc -eq 1 ] && grep -q "no open pull request" "$work/err"' "rc=$rc $(cat "$work/err")"

printf '\n%s failure(s)\n' "$failures"
[ "$failures" -eq 0 ]
