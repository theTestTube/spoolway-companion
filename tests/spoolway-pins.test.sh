#!/usr/bin/env bash
# Offline test for the `pin` mode of the shipped pins.sh: the merge of origin/<base> it does when
# the branch conflicts with the base only in the pages' `verified_commit:`/`verified:` lines. It
# runs against a bare remote and a fake stale-pages gate, in repositories made here. Nothing
# reaches the network. Usage: tests/spoolway-pins.test.sh (needs bash and git)

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

# setup <name>: a consumer with one page citing code.txt, a fake gate that is RED while the page's
# pin is the `basepin` placeholder, a bare origin, and a task document on `pin`. Sets $app, $task,
# $scratch.
setup() {
  local name=$1
  app="$work/$name"; task="$work/$name.md"; scratch="$work/$name-scratch"
  mkdir -p "$app/pages" "$app/.spoolway" "$app/scripts/spoolway" "$scratch"
  cp "$shipped/pins.sh" "$shipped/lib.sh" "$app/scripts/spoolway/"
  git init -q -b main "$app"
  printf 'base\n' > "$app/code.txt"
  printf 'other\n' > "$app/other.txt"
  printf -- '---\nverified_commit: basepin\nverified: 2026-01-01\n---\n\nBody.\n' > "$app/pages/example.md"
  printf 'PAGES_DIR=pages\nPAGES_GATE=bash gate.sh\n' > "$app/.spoolway/companion.env"
  cat > "$app/gate.sh" <<'GATE'
#!/bin/sh
# RED while the page's pin is not a commit that already has the cited code.txt: the real stale-pages
# verdict as a record (STALE_PAGES_RECORDS=1), small enough for a fixture.
red=0
for p in pages/*.md; do
  [ -f "$p" ] || continue
  slug=$(basename "$p" .md); v=$(sed -n 's/^verified_commit: //p' "$p" | head -1)
  if ! git rev-parse -q --verify "$v^{commit}" > /dev/null 2>&1 || ! git diff --quiet "$v" -- code.txt; then
    red=1
    hex=$(printf '%s' "$v" | grep -E '^[0-9a-f]{40}$' || true)
    hist=false; git rev-parse -q --verify "$v^{commit}" > /dev/null 2>&1 && hist=true
    printf '%s\t%s\t%s\t\tcode.txt\tbranch\tn/a\n' "$slug" "$hex" "$hist"
  fi
done
if [ "$red" = 1 ]; then echo '=== RED'; exit 1; else echo '=== GREEN'; exit 0; fi
GATE
  chmod +x "$app/gate.sh"
  git -C "$app" add -A
  git -C "$app" commit -q -m init
  git init -q --bare "$work/$name-origin.git"
  git -C "$app" remote add origin "$work/$name-origin.git"
  git -C "$app" push -q origin main
  printf -- '---\nid: %s\nstage: pin\nbase: main\n---\n\nBody.\n' "$name" > "$task"
}

# a_branch <pin-commit>: a task branch whose code change is $squashed, optionally with a pin commit.
a_branch() {
  git -C "$app" checkout -q -b task/demo
  printf 'branch\n' > "$app/code.txt"
  git -C "$app" add code.txt
  git -C "$app" commit -q -m "feat: change code"
  squashed=$(git -C "$app" rev-parse HEAD)
  if [ "${1:-}" = pin-commit ]; then
    printf -- '---\nverified_commit: %s\nverified: 2026-02-01\n---\n\nBody.\n' "$squashed" > "$app/pages/example.md"
    git -C "$app" add pages
    git -C "$app" commit -q -m "docs(pages): move the drift pin"
  fi
  git -C "$app" push -q origin task/demo
}

# the record names the commit the branch's change is at, so the page is judged against it.
record() { printf 'example | holds | %s | the page still says what code.txt does\n' "$squashed" > "$scratch/stale-pages.md"; }

run() {
  (cd "$app" && SPOOLWAY_TASK_FILE="$task" SPOOLWAY_TASK="$(basename "$task" .md)" SPOOLWAY_SCRATCH="$scratch" \
    bash scripts/spoolway/pins.sh pin) > "$work/out" 2> "$work/err"
  rc=$?
}
mergeable() { git -C "$app" merge-tree --write-tree --quiet HEAD "origin/main" > /dev/null 2>&1; }

# --- A first run with a clean base: no merge, the pin lands on the squashed commit -------------

setup clean
a_branch
record
run
check "a clean base pins without merging" '[ $rc -eq 0 ] && [ "$(git -C "$app" rev-list --count --merges main..HEAD)" -eq 0 ]' "rc=$rc $(cat "$work/out" "$work/err")"
check "the page is pinned to the squashed commit" 'grep -q "verified_commit: $squashed" "$app/pages/example.md"' "$(cat "$app/pages/example.md")"
check "the branch is two commits on, neither a merge" '[ "$(git -C "$app" rev-list --count main..HEAD)" -eq 2 ] && [ "$(git -C "$app" rev-list --count --merges main..HEAD)" -eq 0 ]' "$(git -C "$app" log --oneline -4)"

# A second run pushes the same pin commit and changes nothing.
before=$(git -C "$app" rev-parse HEAD)
run
check "a second run pushes the pin commit already there" '[ $rc -eq 0 ] && grep -q "already on the branch" "$work/out"' "rc=$rc $(cat "$work/out" "$work/err")"
check "a second run makes no new commit" '[ "$(git -C "$app" rev-parse HEAD)" = "$before" ]'

# --- A conflict only in the pages' pin lines: merge origin/base, keep the pins, pin to it -------

setup merge
a_branch pin-commit
record
git -C "$app" checkout -q main
printf -- '---\nverified_commit: basepin2\nverified: 2026-03-01\n---\n\nBody.\n' > "$app/pages/example.md"
git -C "$app" commit -q -am "docs: the base moves the pin"
git -C "$app" push -q origin main
git -C "$app" checkout -q task/demo
run
check "a pin-lines-only conflict passes by merging the base" '[ $rc -eq 0 ] && grep -q "merged origin/main, keeping this branch.s pins" "$work/out"' "rc=$rc $(cat "$work/out" "$work/err")"
check "the pin re-runs pins.sh check after the merge" 'grep -q "^check:" "$work/out"' "$(cat "$work/out")"
check "the merge commit is on the branch" '[ "$(git -C "$app" rev-list --count --merges main..HEAD)" -eq 1 ]' "$(git -C "$app" log --oneline --graph -6)"
check "the page is pinned to the merge commit" 'm=$(git -C "$app" rev-parse HEAD~1); grep -q "verified_commit: $m" "$app/pages/example.md"' "$(cat "$app/pages/example.md")"
check "the branch no longer conflicts with origin/main" 'mergeable' "$(git -C "$app" merge-tree --write-tree HEAD origin/main 2>&1 | head -3)"

# --- A conflict beyond the pin lines: a person resolves it, nothing is merged -------------------

setup other
a_branch
record
git -C "$app" checkout -q main
printf 'the base changed it\n' > "$app/other.txt"
git -C "$app" commit -q -am "chore: the base changes another file"
git -C "$app" push -q origin main
git -C "$app" checkout -q task/demo
printf 'the branch changed it\n' > "$app/other.txt"
git -C "$app" add other.txt
git -C "$app" commit -q -m "chore: the branch changes another file"
top=$(git -C "$app" rev-parse HEAD)
run
check "a conflict beyond the pin lines fails, naming the file" '[ $rc -eq 1 ] && grep -q "more than the pages. pin lines" "$work/err" && grep -q "other.txt" "$work/err"' "rc=$rc $(cat "$work/err")"
check "nothing was merged or pushed" '[ "$(git -C "$app" rev-parse HEAD)" = "$top" ] && ! grep -q "pin:.*pushed" "$work/out"'

printf '\n%s failure(s)\n' "$failures"
[ "$failures" -eq 0 ]
