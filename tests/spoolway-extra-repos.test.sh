#!/usr/bin/env bash
# Runs the companion's extra-* script templates (claude-plugin/templates/scripts/spoolway/) as the
# Developing pipeline does, in a task worktree of a consumer with one extra repository: the
# worktree is cut, the branch pushed and its pull request opened, the checks waited on, the
# worktree removed. Every remote is a bare repository made here; `gh` is a fake that keeps its pull
# requests and comments in files, prints what the real one prints (a `--jq` answer ends in a
# newline), and logs every call. Nothing reaches GitHub or the network.
# Usage: tests/spoolway-extra-repos.test.sh (needs bash, git and jq)

set -u
unset "${!SPOOLWAY_@}" EXTRA_REPOS EXTRA_WORKTREE_ROOT COMPANION_ENV_FILE CI_WAIT_SECONDS CI_POLL_SECONDS
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

repo="$(cd "$(dirname "$0")/.." && pwd)"
templates="$repo/claude-plugin/templates/scripts/spoolway"
work="$(mktemp -d)"
[ -n "${KEEP:-}" ] || trap 'rm -rf "$work"' EXIT

failures=0
cl=clo # a closing keyword is built at runtime: this file must not write one before an issue itself
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1" "${3:-}"; fi; }

# --- The consumer: shop beside its extra repository lib, each with a bare origin ---------------

top=$work/code
mkdir -p "$top" "$work/remotes" "$work/bin" "$work/gh" "$work/state"
git init -q --bare -b main "$work/remotes/lib.git"
git clone -q "$work/remotes/lib.git" "$top/lib" 2> /dev/null
echo lib > "$top/lib/lib.txt"
git -C "$top/lib" add -A && git -C "$top/lib" commit -q -m init && git -C "$top/lib" push -q origin main

git init -q --bare -b main "$work/remotes/shop.git"
git clone -q "$work/remotes/shop.git" "$top/shop" 2> /dev/null
mkdir -p "$top/shop/scripts/spoolway" "$top/shop/.spoolway"
cp "$repo/claude-plugin/spoolway/types/scripts/spoolway/lib.sh" "$templates"/extra-*.sh "$top/shop/scripts/spoolway/"
printf 'EXTRA_REPOS=acme/lib\nEXTRA_WORKTREE_ROOT=../worktrees\n' > "$top/shop/.spoolway/companion.env"
git -C "$top/shop" add -A && git -C "$top/shop" commit -q -m init && git -C "$top/shop" push -q origin main
# The task's worktree sits elsewhere, as spoolway cuts it: nothing is read relative to it.
git -C "$top/shop" worktree add -q -b task/demo "$work/spoolway/worktrees/t1" main
wt=$work/spoolway/worktrees/t1
lib_wt=$top/shop/../worktrees/lib/task-demo

# fake gh. Pull requests live in $work/gh/pr-<repo>, one URL; checks in $work/gh/checks (JSON).
export GH_DIR=$work/gh
cat > "$work/bin/gh" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
echo "gh $* @$(basename "$(git rev-parse --show-toplevel 2> /dev/null || pwd)")" >> "$GH_DIR/calls"
name=$(basename "$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null | xargs dirname 2> /dev/null || pwd)")
case "$1 $2" in
  "pr list") [ -f "$GH_DIR/pr-$name" ] && cat "$GH_DIR/pr-$name"; echo ;;
  "pr create")
    while [ $# -gt 0 ]; do case $1 in --body-file) cp "$2" "$GH_DIR/body-$name" ;; --base) echo "$2" > "$GH_DIR/base-$name" ;; esac; shift; done
    echo "https://github.com/acme/$name/pull/9" > "$GH_DIR/pr-$name.tmp"; printf '%s' "$(cat "$GH_DIR/pr-$name.tmp")" > "$GH_DIR/pr-$name"; rm "$GH_DIR/pr-$name.tmp"
    echo "https://github.com/acme/$name/pull/9" ;;
  "pr view") cat "$GH_DIR/closing" 2> /dev/null || true; echo ;;
  "pr checks") cat "$GH_DIR/checks" 2> /dev/null || echo '[]' ;;
  "issue view") cat "$GH_DIR/comments" 2> /dev/null || true; echo ;;
  "issue comment") shift 3; printf '%s\n' "$2" >> "$GH_DIR/comments" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 2 ;;
esac
FAKE
chmod +x "$work/bin/gh"

task=$work/state/queue/t1.md
mkdir -p "$(dirname "$task")"
# make_task <stage> [<frontmatter line>...]
make_task() {
  local stage=$1; shift
  { printf -- '---\nid: t1\nstage: %s\ntitle: feat(lib): a change\nstarts_from: main\nbase: develop\nsource: https://github.com/acme/shop/issues/42\n' "$stage"
    [ $# -gt 0 ] && printf '%s\n' "$@"
    printf -- '---\n\nPart of #42.\n'; } > "$task"
}
# run <step>: the step's script, run in the task worktree as the dispatcher runs it.
run() {
  (cd "$wt" && PATH="$work/bin:$PATH" SPOOLWAY_TASK_FILE="$task" SPOOLWAY_TASK=t1 CI_POLL_SECONDS=0 bash "scripts/spoolway/$1.sh") > "$work/out" 2> "$work/err"
  rc=$?
}
log() { cat "$work/out" "$work/err"; }

# --- No extra repository named ---------------------------------------------------------------

for step in extra-worktree extra-handover extra-cleanup; do
  make_task "$step"
  run "$step"
  check "$step passes at once for a task with no repos" '[ $rc -eq 0 ] && grep -q "passing at once" "$work/out"' "rc=$rc $(log)"
  make_task "$step" "repos: [shop]"
  run "$step"
  check "$step passes at once when repos names this repository alone" '[ $rc -eq 0 ] && grep -q "passing at once" "$work/out"' "rc=$rc $(log)"
  make_task "$step" "repos: [shop, acme/typo]"
  run "$step"
  check "$step blocks on an entry that is neither this repository nor an extra one" '[ $rc -eq 1 ] && grep -q "^ENVIRONMENT:.*typo" "$work/err"' "rc=$rc $(log)"
done
check "nothing was cut, pushed or asked of gh" '[ ! -e "$lib_wt" ] && [ ! -s "$GH_DIR/calls" ]' "$(cat "$GH_DIR/calls" 2> /dev/null)"

# --- extra-worktree --------------------------------------------------------------------------

make_task extra-worktree "repos: [shop, acme/lib]"
run extra-worktree
check "extra-worktree cuts the lib worktree on the task's branch, under the root read from the main checkout" \
  '[ $rc -eq 0 ] && [ "$(git -C "$lib_wt" rev-parse --abbrev-ref HEAD)" = task/demo ]' "rc=$rc $(log)"
check "it starts from lib's default branch when lib has no \`base\` branch" \
  '[ "$(git -C "$lib_wt" rev-parse HEAD)" = "$(git -C "$top/lib" rev-parse origin/main)" ] && grep -q "from origin/main" "$work/out"' "$(log)"
run extra-worktree
check "a second run, as on a resume, passes on the worktree already there" '[ $rc -eq 0 ] && grep -q "already on task/demo" "$work/out"' "rc=$rc $(log)"

# --- extra-handover --------------------------------------------------------------------------

echo one > "$lib_wt/a.txt"; git -C "$lib_wt" add -A; git -C "$lib_wt" commit -q -m wip
echo two > "$lib_wt/b.txt"; git -C "$lib_wt" add -A; git -C "$lib_wt" commit -q -m "wip 2"
echo dirty > "$lib_wt/c.txt"
make_task extra-handover "repos: [shop, acme/lib]"
run extra-handover
check "extra-handover refuses uncommitted changes and pushes nothing" \
  '[ $rc -eq 1 ] && grep -q "uncommitted" "$work/err" && ! git -C "$work/remotes/lib.git" rev-parse -q --verify refs/heads/task/demo > /dev/null' "rc=$rc $(log)"
rm "$lib_wt/c.txt"

printf '[{"name":"ci","bucket":"pass","link":"l"}]' > "$GH_DIR/checks"
run extra-handover
check "extra-handover passes once every check is green" '[ $rc -eq 0 ] && grep -q "every check is green" "$work/out"' "rc=$rc $(log)"
check "it pushed one commit titled with the task title" \
  '[ "$(git -C "$work/remotes/lib.git" log -1 --format=%s task/demo)" = "feat(lib): a change" ] && [ "$(git -C "$work/remotes/lib.git" rev-list --count main..task/demo)" = 1 ]'
check "it opened the pull request in lib, against lib's default branch, naming the issue by URL" \
  '[ "$(cat "$GH_DIR/base-lib")" = main ] && head -1 "$GH_DIR/body-lib" | grep -qx "Part of https://github.com/acme/shop/issues/42" && grep -q "gh pr create.*@task-demo" "$GH_DIR/calls"' "$(cat "$GH_DIR/body-lib" "$GH_DIR/calls")"
check "a task that changed only lib comments once on its issue" '[ "$(grep -c "pull/9" "$GH_DIR/comments")" = 1 ]' "$(cat "$GH_DIR/comments")"
creates=$(grep -c "pr create" "$GH_DIR/calls")
run extra-handover
check "a second run opens no second pull request and posts no second comment" \
  '[ $rc -eq 0 ] && [ "$(grep -c "pr create" "$GH_DIR/calls")" = "$creates" ] && [ "$(grep -c "pull/9" "$GH_DIR/comments")" = 1 ]' "rc=$rc $(log)"

printf '[{"name":"ci","bucket":"fail","link":"l"}]' > "$GH_DIR/checks"
run extra-handover
check "a failing check blocks the step" '[ $rc -eq 1 ] && grep -q "failing checks" "$work/err"' "rc=$rc $(log)"
printf '[]' > "$GH_DIR/checks"
(export CI_WAIT_SECONDS=0; run extra-handover; [ $rc -eq 1 ] && grep -q "nothing to wait for is not a pass" "$work/err") && pass "no check at all is not a pass" || fail "no check at all is not a pass" "$(log)"
printf '#42' > "$GH_DIR/closing"
run extra-handover
check "a pull request GitHub reads as closing an issue blocks the step" '[ $rc -eq 1 ] && grep -q "would $cl""se #42" "$work/err"' "rc=$rc $(log)"
rm "$GH_DIR/closing"

# --- extra-cleanup ---------------------------------------------------------------------------

mkdir -p "$lib_wt/.scratch" && echo note > "$lib_wt/.scratch/n.md"
make_task extra-cleanup "repos: [shop, acme/lib]"
run extra-cleanup
check "extra-cleanup leaves a worktree holding .scratch files alone, and passes" '[ $rc -eq 0 ] && [ -d "$lib_wt" ] && grep -q "left alone" "$work/out"' "rc=$rc $(log)"
rm -r "$lib_wt/.scratch"
echo more > "$lib_wt/d.txt"; git -C "$lib_wt" add -A; git -C "$lib_wt" commit -q -m unpushed
run extra-cleanup
check "it leaves a worktree with commits origin lacks alone" '[ $rc -eq 0 ] && [ -d "$lib_wt" ] && grep -q "commits origin does not have" "$work/out"' "rc=$rc $(log)"
git -C "$lib_wt" reset -q --hard origin/task/demo
run extra-cleanup
check "it removes the pushed worktree and its local branch" \
  '[ $rc -eq 0 ] && [ ! -e "$lib_wt" ] && ! git -C "$top/lib" rev-parse -q --verify refs/heads/task/demo > /dev/null' "rc=$rc $(log)"
run extra-cleanup
check "a second run finds nothing to remove and passes" '[ $rc -eq 0 ] && grep -q "nothing to remove" "$work/out"' "rc=$rc $(log)"

# --- The keys -------------------------------------------------------------------------------

make_task extra-worktree "repos: [shop, lib]"
(cd "$wt" && PATH="$work/bin:$PATH" SPOOLWAY_TASK_FILE="$task" EXTRA_WORKTREE_ROOT= COMPANION_ENV_FILE=/dev/null EXTRA_REPOS=lib bash scripts/spoolway/extra-worktree.sh) > "$work/out" 2> "$work/err"; rc=$?
check "a missing EXTRA_WORKTREE_ROOT blocks with ENVIRONMENT, naming the key" '[ $rc -eq 1 ] && grep -q "^ENVIRONMENT: EXTRA_WORKTREE_ROOT" "$work/err"' "rc=$rc $(log)"
mv "$top/lib" "$top/lib.away"
run extra-worktree
check "a missing extra checkout blocks with ENVIRONMENT" '[ $rc -eq 1 ] && grep -q "^ENVIRONMENT: no checkout of lib" "$work/err"' "rc=$rc $(log)"
mv "$top/lib.away" "$top/lib"

# --- A consumer with no extra repository: EXTRA_REPOS empty -----------------------------------

for step in extra-worktree extra-handover extra-cleanup; do
  make_task "$step" "repos: [project]"
  (cd "$wt" && PATH="$work/bin:$PATH" SPOOLWAY_TASK_FILE="$task" COMPANION_ENV_FILE=/dev/null bash "scripts/spoolway/$step.sh") > "$work/out" 2> "$work/err"; rc=$?
  check "mono: $step passes at once when repos names one repository, under any name" '[ $rc -eq 0 ] && grep -q "passing at once" "$work/out"' "rc=$rc $(log)"
  make_task "$step" "repos: [project, extra-lib]"
  (cd "$wt" && PATH="$work/bin:$PATH" SPOOLWAY_TASK_FILE="$task" COMPANION_ENV_FILE=/dev/null bash "scripts/spoolway/$step.sh") > "$work/out" 2> "$work/err"; rc=$?
  check "mono: $step blocks when repos names a second repository" '[ $rc -eq 1 ] && grep -q "^ENVIRONMENT:.*EXTRA_REPOS.*empty" "$work/err"' "rc=$rc $(log)"
done

# --- The content rule -----------------------------------------------------------------------

check "the templates carry the written-once header and name no project or personal path" \
  'for f in "$templates"/extra-*.sh; do sed -n 2p "$f" | grep -q "^# Written once by /spoolway-companion:setup" || exit 1; done; ! grep -niE "i[- ]?ching|/home/|herdr" "$templates"/extra-*.sh'

echo
if [ "$failures" -eq 0 ]; then echo "all passed"; else echo "$failures failed"; exit 1; fi
