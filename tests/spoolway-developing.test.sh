#!/usr/bin/env bash
# Offline test for this repository's Developing pipeline scripts: the command steps
# the types do not ship (scripts/spoolway/checks.sh, handover.sh, extra-*.sh),
# scripts/gates/run.sh, and the shipped pins.sh with and without a pages directory, its record
# contract and its no-wiki stub. It
# also fails when the gates of checks.sh and the Gates job of .github/workflows/ci.yml run different
# commands. `git` is the real one, against repositories made here; `spoolway` and `gh` are
# fakes that record their calls. Nothing reaches GitHub or the network, and no dispatcher starts.
# Usage: tests/spoolway-developing.test.sh (needs bash, git and awk)

set -u

# Nothing from the caller's environment: the checks step runs this suite inside a task, with the
# dispatcher's SPOOLWAY_* set, and a CI runner has no git identity for the commits made here.
unset "${!SPOOLWAY_@}"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
cl=clo # a closing keyword is built at runtime: this file must not write one before an issue itself
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1" "${3:-}"; fi; }

# --- The gates of checks.sh and of the Gates job ---------------------------------------------

in_checks=$(awk '/^# gates: end/ { on = 0 } on { print } /^# gates: begin/ { on = 1 }' "$repo/scripts/spoolway/checks.sh")
# The run block of the step named Gates, indentation taken off, up to the next line that is less indented.
in_ci=$(awk '
  /^      - name: Gates[[:space:]]*$/ { step = 1; next }
  step && /^        run: \|[[:space:]]*$/ { on = 1; next }
  on && /^          / { sub(/^          /, ""); print; next }
  on { exit }' "$repo/.github/workflows/ci.yml")
check "checks.sh has gates" '[ -n "$in_checks" ]'
check "the Gates job runs the commands of checks.sh, in order" '[ "$in_checks" = "$in_ci" ]' \
  "checks.sh: $(printf '%s' "$in_checks" | tr '\n' ';')  ci.yml: $(printf '%s' "$in_ci" | tr '\n' ';')"
check "the job is named Gates" 'grep -qE "^    name: Gates$" "$repo/.github/workflows/ci.yml"'
check "checks.sh runs the machine-keys gate first" 'printf "%s\n" "$in_checks" | head -1 | grep -qxF "scripts/gates/run.sh machine-keys"'
check "checks.sh runs every tests/*.test.sh" 'printf "%s\n" "$in_checks" | grep -qxF "for t in tests/*.test.sh; do bash \"\$t\"; done"'
check "checks.sh runs spoolway pipeline check" 'printf "%s\n" "$in_checks" | grep -q "spoolway pipeline check"'

# --- A repository laid out like this one -----------------------------------------------------

app="$work/app"
mkdir -p "$app/scripts/spoolway" "$app/scripts/gates" "$work/bin" "$work/state"
cp "$repo"/scripts/spoolway/*.sh "$app/scripts/spoolway/"
# The plugin source is canonical for a shipped script: the installed copy is the revision this
# repository took, and this suite drives what the plugin would write.
cp "$repo"/claude-plugin/spoolway/types/scripts/spoolway/pins.sh "$app/scripts/spoolway/pins.sh"
cp -r "$repo"/scripts/gates/. "$app/scripts/gates/"
git -C "$app" init -q -b main
git -C "$app" add -A
git -C "$app" commit -q -m init
git -C "$app" checkout -q -b task/demo
echo change > "$app/file.txt"
git -C "$app" add file.txt
git -C "$app" commit -q -m "feat(demo): a change"

# fake spoolway and gh: every call logged in $CALLS. `gh pr list` answers 7 once `spoolway stack` ran,
# `gh pr view` answers the body (with the trailer) or no closing references, `gh pr edit` stores the body.
export CALLS="$work/calls" BODY_OUT="$work/body.out" CLOSING=
cat > "$work/bin/spoolway" <<'FAKE'
#!/bin/sh
echo "spoolway $*" >> "$CALLS"
[ "$1" = stack ] && touch "$CALLS.stacked"
exit 0
FAKE
cat > "$work/bin/gh" <<'FAKE'
#!/bin/sh
echo "gh $*" >> "$CALLS"
case "$1 $2" in
  "pr list") [ -f "$CALLS.stacked" ] && [ -z "${FAKE_NO_PR:-}" ] && echo 7 ;;
  "pr view")
    case "$*" in
      *closingIssuesReferences*) printf '%s' "$CLOSING" ;;
      *) printf 'The change.\n\nCo-Authored-By: Claude Code <noreply@anthropic.com>\n' ;;
    esac ;;
  "pr edit") while [ $# -gt 0 ]; do [ "$1" = --body-file ] && cp "$2" "$BODY_OUT"; shift; done ;;
esac
exit 0
FAKE
chmod +x "$work/bin/spoolway" "$work/bin/gh"

# task <stage> [<extra frontmatter line>...]: a task document on that stage, path in $task.
task=$work/state/t1.md
make_task() {
  local stage=$1; shift
  { printf -- '---\nid: t1\nstage: %s\ntitle: %s\nstarts_from: main\n' "$stage" "${TITLE:-'feat(demo): a change'}"
    [ $# -gt 0 ] && printf '%s\n' "$@"
    printf -- '---\n\n%s\n' "${BODY:-Part of #1.}"; } > "$task"
}
# run <script> [<args>]: the script in the fixture repository, as the dispatcher runs a step.
run() {
  local script=$1; shift
  (cd "$app" && PATH="$work/bin:$PATH" SPOOLWAY_TASK_FILE="$task" SPOOLWAY_TASK=t1 bash "scripts/spoolway/$script" "$@") > "$work/out" 2> "$work/err"
  rc=$?
}

# --- The extra steps pass at once ------------------------------------------------------------

for step in extra-worktree extra-handover extra-cleanup; do
  make_task "$step" "repos: [project]"
  run "$step.sh"
  check "$step passes at once when repos names this repository alone" '[ $rc -eq 0 ] && grep -q "passing at once" "$work/out"' "rc=$rc $(cat "$work/out" "$work/err")"
  make_task "$step"
  run "$step.sh"
  check "$step passes at once when the task has no repos" '[ $rc -eq 0 ]'
  make_task "$step" "repos: [project, extra-lib]"
  run "$step.sh"
  check "$step blocks when repos names another repository" '[ $rc -eq 1 ] && grep -q "^ENVIRONMENT:" "$work/err"' "rc=$rc $(cat "$work/err")"
  make_task "$step" "repos: [project, extra-lib]" "skip_steps: [$step]"
  run "$step.sh"
  check "$step passes at once when skip_steps names it" '[ $rc -eq 0 ]'
  make_task checks "repos: [project]"
  run "$step.sh"
  check "$step refuses to run on another step's stage" '[ $rc -eq 64 ]'
  run "$step.sh" --help
  check "$step takes no argument" '[ $rc -eq 64 ]'
done

# --- checks.sh: its guards, not its gates (those are this suite and spoolway itself) -----------

make_task checks "skip_steps: [checks]"
run checks.sh
check "checks passes at once when skip_steps names it" '[ $rc -eq 0 ] && grep -q "passing at once" "$work/out"'
make_task handover
run checks.sh
check "checks refuses to run on another step's stage" '[ $rc -eq 64 ]'

# --- pins.sh with and without a pages directory ----------------------------------------------

make_task pin
run pins.sh pin
check "pins.sh pin passes at once and pushes nothing with no pages directory" '[ $rc -eq 0 ] && grep -q "no pages directory is named" "$work/out" && ! grep -q "push" "$CALLS" 2>/dev/null' "rc=$rc $(cat "$work/out" "$work/err")"
make_task checks
run pins.sh check
check "pins.sh check passes at once with no pages directory" '[ $rc -eq 0 ] && grep -q "no pages directory is named" "$work/out"' "rc=$rc $(cat "$work/err")"
# A consumer that names one: a stub gate that answers GREEN, then one that fails naming no page.
mkdir -p "$app/.spoolway" "$app/pages"
printf 'PAGES_DIR=./pages/\nPAGES_GATE="echo === GREEN — 1 green"\n' > "$app/.spoolway/companion.env"
make_task checks
run pins.sh check
check "pins.sh check runs the named gate when companion.env names a pages directory" '[ $rc -eq 0 ] && grep -q "echo === GREEN" "$work/out"' "rc=$rc $(cat "$work/out" "$work/err")"
printf 'PAGES_DIR=pages\nPAGES_GATE=exit 1\n' > "$app/.spoolway/companion.env"
run pins.sh check
check "pins.sh check does not call a failed gate that named no page green" '[ $rc -ne 0 ] && grep -q "^ENVIRONMENT:" "$work/err"' "rc=$rc $(cat "$work/out" "$work/err")"
rm -rf "$app/.spoolway" "$app/pages"
check "the runner refuses a gate it does not know" '! bash "$app/scripts/gates/run.sh" budget 2>/dev/null'

# --- pins.sh consumes the drift record contract -----------------------------------------------

stub="$repo/claude-plugin/spoolway/types/scripts/spoolway/stale-pages-stub.sh"
STALE_PAGES_RECORDS=1 bash "$stub" > "$work/out" 2> "$work/err"; rc=$?
check "the no-wiki stub answers the records mode with GREEN" '[ $rc -eq 0 ] && grep -q "^=== GREEN" "$work/out"' "rc=$rc $(cat "$work/out" "$work/err")"

mkdir -p "$app/pages" "$app/.spoolway"
cat > "$app/pages/foo.md" <<'PAGE'
---
title: Foo
source_commit: deadbeef
---

Cites `file.txt`.
PAGE
git -C "$app" add pages/foo.md
git -C "$app" commit -q -m "docs(pages): add foo"
head=$(git -C "$app" rev-parse HEAD)
# A gate that speaks the contract: the page's pin is off history, and one real path changed.
cat > "$app/gate.sh" <<'GATE'
#!/usr/bin/env bash
printf 'foo\tdeadbeef\tfalse\t\tfile.txt\tbranch\tn/a\n'
exit 1
GATE
chmod +x "$app/gate.sh"
printf 'PAGES_DIR=pages\nPAGES_GATE=%s/gate.sh\n' "$app" > "$app/.spoolway/companion.env"
mkdir -p "$work/scratch/t1"
printf 'foo | holds | %s | the page still says what file.txt does\n' "$head" > "$work/scratch/t1/stale-pages.md"
make_task checks
run pins.sh check
check "pins.sh reads a record's changed field, never its off-history flag, as the cited path" \
  '[ $rc -eq 0 ] && grep -q -- "-- file.txt" "$work/out" && ! grep -q "not in history" "$work/out"' \
  "rc=$rc $(cat "$work/out" "$work/err")"

# An off-history record that names no path: the flag is a field, never a cited path.
cat > "$app/gate.sh" <<'GATE'
#!/usr/bin/env bash
printf 'foo\tdeadbeef\tfalse\t\t\tbranch\tn/a\n'
exit 1
GATE
chmod +x "$app/gate.sh"
run pins.sh check
check "an off-history record with no changed path is never read as one" \
  '[ $rc -ne 0 ] && ! grep -q "git diff .* -- " "$work/out" "$work/err" && grep -q "not in history" "$work/err"' \
  "rc=$rc $(cat "$work/out" "$work/err")"

# A red the base carries: reported, and this branch owes nothing.
cat > "$app/gate.sh" <<'GATE'
#!/usr/bin/env bash
printf 'foo\tdeadbeef\tfalse\t\tfile.txt\tbase\tn/a\n'
exit 1
GATE
chmod +x "$app/gate.sh"
run pins.sh check
check "pins.sh reports a base-owed red without blocking" \
  '[ $rc -eq 0 ] && grep -q "red from the base, not this branch" "$work/out"' \
  "rc=$rc $(cat "$work/out" "$work/err")"
rm -rf "$app/.spoolway" "$app/pages" "$work/scratch"

# --- collect.sh (shipped; the last step, no on_fail, so a failure parks every task) ------------

home=$work/home
mkdir -p "$home/queue" "$home/scratch/t1/nested" "$home/commands"
echo notes > "$home/scratch/t1/nested/notes.md"
echo log > "$home/commands/t1 · checks.log"
echo other > "$home/commands/t2 · checks.log"
printf -- '---\nid: t1\nstage: collect\ntitle: x\n---\nbody\n' > "$home/queue/t1.md"
printf '.scratch/\n' > "$app/.gitignore"
saved=$task
task=$home/queue/t1.md
run collect.sh --keep-days 90
check "collect copies the scratch space and the command logs to the main checkout" \
  '[ $rc -eq 0 ] && [ -f "$app/.scratch/spoolway/t1/scratch/nested/notes.md" ] && [ -f "$app/.scratch/spoolway/t1/commands/t1 · checks.log" ] && [ ! -e "$app/.scratch/spoolway/t1/commands/t2 · checks.log" ]' \
  "rc=$rc $(cat "$work/out" "$work/err")"
rm -f "$app/.gitignore"
run collect.sh --keep-days 90
check "collect fails, naming .gitignore, when .scratch/ is not git-ignored" '[ $rc -eq 1 ] && grep -q "not git-ignored" "$work/err"'
task=$saved

# The shipped copy (the pinned one above is the previous revision): a scratch space holding a link to a
# directory, to a file and to nothing is collected, each link kept as a link, none followed.
cp "$repo/claude-plugin/spoolway/types/scripts/spoolway/collect.sh" "$app/scripts/spoolway/collect.sh"
outside=$work/outside
mkdir -p "$outside/dir"
echo secret > "$outside/dir/secret.txt"
echo secret > "$outside/file.txt"
mkdir -p "$home/scratch/t1/disc"
ln -s "$outside/dir" "$home/scratch/t1/disc/dirlink"
ln -s "$outside/file.txt" "$home/scratch/t1/disc/filelink"
ln -s "$outside/missing" "$home/scratch/t1/disc/dangling"
ln -s ../nested "$home/scratch/t1/disc/relative"
printf '.scratch/\n' > "$app/.gitignore"
rm -rf "$app/.scratch"
task=$home/queue/t1.md
run collect.sh --keep-days 90
tsv=$app/.scratch/spoolway/t1/collect.tsv
check "collect exits 0 on a scratch space holding a link to a directory, to a file and a dangling one" \
  '[ $rc -eq 0 ]' "rc=$rc $(cat "$work/out" "$work/err")"
check "collect.tsv says what was done with each link" \
  'grep -qF "disc/dirlink -> $outside/dir" "$tsv" && grep -qF "disc/filelink -> $outside/file.txt" "$tsv" && grep -qF "disc/dangling -> $outside/missing" "$tsv" && grep -qF "disc/relative -> ../nested" "$tsv"' "$(cat "$tsv" 2>/dev/null)"
check "collect keeps each link as a link with its own target" \
  'c=$app/.scratch/spoolway/t1/scratch/disc; [ "$(readlink "$c/dirlink")" = "$outside/dir" ] && [ "$(readlink "$c/filelink")" = "$outside/file.txt" ] && [ -L "$c/dangling" ]'
check "collect follows no link out of the scratch space" \
  '! grep -rq secret "$app/.scratch/spoolway/t1/scratch/disc/" 2>/dev/null; [ ! -e "$app/.scratch/spoolway/t1/scratch/disc/dirlink/secret.txt" ] || [ -L "$app/.scratch/spoolway/t1/scratch/disc/dirlink" ]; ! find "$app/.scratch/spoolway/t1" -type f -name "secret*" | grep -q .; ! find "$app/.scratch/spoolway/t1" -type f -name "file.txt" | grep -q .'
run collect.sh --keep-days 90
check "collect run again over the same links changes nothing and passes" \
  '[ $rc -eq 0 ] && ! find "$app/.scratch/spoolway/t1/scratch/disc" -name "*~" | grep -q .'
rm -f "$app/.gitignore"
rm -rf "$app/.scratch"
task=$saved

# --- handover.sh -------------------------------------------------------------------------------

TITLE="'Feat: A Change'" make_task handover
run handover.sh
check "handover refuses a title that is not a conventional commit" '[ $rc -eq 1 ] && ! grep -q stack "$CALLS" 2>/dev/null' "rc=$rc $(cat "$work/err")"

BODY="This ${cl}ses #12." make_task handover
rm -f "$CALLS" "$CALLS.stacked"
run handover.sh
check "handover refuses a closing keyword before any push" '[ $rc -eq 1 ] && ! grep -q stack "$CALLS" 2>/dev/null'

make_task handover "requires: example/app#9"
rm -f "$CALLS" "$CALLS.stacked" "$BODY_OUT"
run handover.sh
check "handover stacks, takes the trailer off and writes what the task waits on" \
  '[ $rc -eq 0 ] && grep -q "^spoolway stack" "$CALLS" && grep -q "^## Waits on" "$BODY_OUT" && ! grep -qi "co-authored" "$BODY_OUT"' \
  "rc=$rc $(cat "$work/err") $(cat "$BODY_OUT" 2>/dev/null)"

make_task handover
rm -f "$CALLS" "$CALLS.stacked"
FAKE_NO_PR=1 run handover.sh
check "handover fails when the branch has no pull request after stack" '[ $rc -eq 1 ] && grep -q "no pull request open" "$work/err"'

make_task handover
rm -f "$CALLS" "$CALLS.stacked"
CLOSING="#12" run handover.sh
check "handover fails when GitHub parsed a closing reference" '[ $rc -eq 1 ] && grep -q "would ${cl}se #12" "$work/err"'

echo
if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failure(s)"
  exit 1
fi
