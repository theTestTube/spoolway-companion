#!/usr/bin/env bash
# Offline test for the materializing-* scripts under the plugin's types
# (claude-plugin/spoolway/types/scripts/spoolway/): each one copied into a consumer made here,
# beside the types' lib.sh, and run as the dispatcher runs it.
# `git` is the real one; `gh` and `spoolway` are fakes. Nothing reaches GitHub or the network.
# Usage: tests/spoolway-materializing-templates.test.sh (needs bash, git and awk)

set -u
unset "${!SPOOLWAY_@}" MATERIALIZING_REPO PAGES_DIR PAGES_LOG
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

repo="$(cd "$(dirname "$0")/.." && pwd)"
types_scripts="$repo/claude-plugin/spoolway/types/scripts/spoolway"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1" "${3:-}"; fi; }

for s in bind backing drafts gates handover; do
  f=$types_scripts/materializing-$s.sh
  check "materializing-$s.sh is executable and carries the shipped-types header" \
    '[ -x "$f" ] && sed -n 2p "$f" | grep -q "^# Shipped with the Materializing pipeline"'
done

# --- a consumer -------------------------------------------------------------------------------

c="$work/consumer"
home="$work/home"
mkdir -p "$c/scripts/spoolway" "$c/.spoolway" "$home/queue" "$home/scratch/m1" "$work/bin"
cp "$repo/claude-plugin/spoolway/types/scripts/spoolway/lib.sh" "$c/scripts/spoolway/"
cp -p "$types_scripts"/materializing-*.sh "$c/scripts/spoolway/"
printf '#!/bin/sh\necho "handover.sh ran"\n' > "$c/scripts/spoolway/handover.sh"
printf '#!/bin/sh\necho "pins.sh $*"\n' > "$c/scripts/spoolway/pins.sh"
chmod +x "$c/scripts/spoolway/handover.sh" "$c/scripts/spoolway/pins.sh"
echo "# glossary" > "$c/CONTEXT.md"
echo "code" > "$c/src.txt"
git -C "$c" init -q -b develop
git -C "$c" add -A
git -C "$c" commit -q -m init
git -C "$c" checkout -q -b task/m1

export PATH="$work/bin:$PATH" GH_STATE=OPEN CONTRACT_RC=0
cat > "$work/bin/gh" <<'FAKE'
#!/bin/sh
case "$1 $2" in
  "issue view") case " $* " in *" --json state "*) echo "$GH_STATE" ;; *) case "$3" in 404) exit 1 ;; *) echo "$3" ;; esac ;; esac ;;
  "repo view") echo acme/shop ;;
  *) exit 1 ;;
esac
FAKE
cat > "$work/bin/spoolway" <<'FAKE'
#!/bin/sh
[ "$CONTRACT_RC" -eq 0 ] || echo "contract: refused"
exit "$CONTRACT_RC"
FAKE
chmod +x "$work/bin/gh" "$work/bin/spoolway"

spec=https://github.com/acme/shop/issues/1
tf="$home/queue/m1.md"
task() { # task <stage> [extra frontmatter lines]
  local stage=$1; shift
  { printf -- '---\nid: m1\npipeline: materializing\nstage: %s\nbase: develop\nticket: %s\n' "$stage" "$spec"
    printf '%s\n' "$@"; printf -- '---\nbody\n'; } > "$tf"
}
export SPOOLWAY_TASK_FILE="$tf" SPOOLWAY_SCRATCH="$home/scratch/m1" SPOOLWAY_REPO="$c"
run() { out=$(cd "$c" && "scripts/spoolway/$@" 2>&1); status=$?; }

# --- bind -------------------------------------------------------------------------------------

task backing 'close_on_merge: false'; run materializing-bind.sh
check "bind refuses to run on another step" '[ $status -eq 64 ]' "$out"
task bind 'close_on_merge: false'; run materializing-bind.sh
check "bind passes an open spec with close_on_merge: false" '[ $status -eq 0 ]' "$out"
task bind; run materializing-bind.sh
check "bind refuses a task without close_on_merge: false" '[ $status -eq 1 ] && grep -q close_on_merge <<<"$out"' "$out"
GH_STATE=CLOSED; task bind 'close_on_merge: false'; run materializing-bind.sh; GH_STATE=OPEN
check "bind refuses a closed spec" '[ $status -eq 1 ] && grep -q CLOSED <<<"$out"' "$out"
task bind 'close_on_merge: false' 'skip_steps: [bind]'; run materializing-bind.sh
check "bind is never skipped" '[ $status -eq 1 ]' "$out"

# --- backing ----------------------------------------------------------------------------------

S=$SPOOLWAY_SCRATCH
cat > "$S/recall.candidates.md" <<'C'
- a claim backed by a file | wiki: none | ref: src.txt
- a claim backed by a bare issue | wiki: none | ref: #7
- a claim backed by nothing | wiki: none | ref: #404, missing.txt
- not a candidate at all
C
task backing; run materializing-backing.sh
check "backing without PAGES_DIR admits on a reference alone, a bare #N against the run's repository" \
  '[ $status -eq 0 ] && [ "$(wc -l < "$S/recall.md")" -eq 2 ] && grep -q "backing: 2 admitted, 2 dropped" <<<"$out"' "$out"
mkdir -p "$c/pages" && echo page > "$c/pages/p1.md"
printf 'PAGES_DIR=pages\n' > "$c/.spoolway/companion.env"
git -C "$c" add -A && git -C "$c" commit -q -m pages
cat > "$S/recall.candidates.md" <<'C'
- a claim on a page | wiki: p1 | ref: src.txt
- a claim on no page | wiki: p2 | ref: src.txt
- a page backing itself | wiki: p1 | ref: pages/p1.md
C
run materializing-backing.sh
check "backing with PAGES_DIR needs the page and refuses a page as its own reference" \
  '[ $status -eq 0 ] && [ "$(wc -l < "$S/recall.md")" -eq 1 ] && grep -q "page \`p1\`" "$S/recall.md" && [ "$(grep -c "dropped:" "$S/recall.dropped.md")" -eq 2 ]' "$out"
git -C "$c" rm -q -r pages .spoolway/companion.env && git -C "$c" commit -q -m "no pages"
rm -f "$S"/recall*

# --- drafts -----------------------------------------------------------------------------------

mkdir -p "$S/drafts"
draft() { # draft <id> <n> <title> [extra]
  { printf -- '---\nid: %s\ntitle: %s\npipeline: developing\nbase: develop\nticket: https://github.com/acme/shop/issues/%s\n' "$1" "$3" "$2"
    [ -n "${4:-}" ] && printf '%s\n' "$4"; printf -- '---\nbody\n'; } > "$S/drafts/$1.md"
}
printf 'Approved by the owner.\n\n## 1. feat(shop): add a cart\n- project: shop\n- repos: shop\n- blocked by: none\n\n## 2. feat(shop): add a checkout\n- project: shop\n- repos: shop\n- blocked by: 1\n' > "$S/breakdown.md"
printf -- '- https://github.com/acme/shop/issues/2 | draft: t-cart\n- https://github.com/acme/shop/issues/3 | draft: t-checkout\n- https://github.com/acme/other/issues/9 | draft: none\n' > "$S/tickets.md"
draft t-cart 2 'feat(shop): add a cart'
draft t-checkout 3 'feat(shop): add a checkout' 'close_on_merge: false'
task drafts; run materializing-drafts.sh
check "drafts refuses a set with one bad draft and writes nothing to pending/" \
  '[ $status -eq 1 ] && [ ! -e "$home/pending/t-cart.md" ] && grep -q close_on_merge "$S/drafts.problems.md"' "$out"
draft t-checkout 3 'feat(shop): add a checkout' 'repos: [shop]'
CONTRACT_RC=1; run materializing-drafts.sh; CONTRACT_RC=0
check "drafts writes nothing when spoolway refuses the set" '[ $status -eq 1 ] && [ ! -e "$home/pending/t-cart.md" ] && grep -q "refused" "$S/drafts.problems.md"' "$out"
run materializing-drafts.sh
check "drafts copies the whole set, a draft with no repos counting as this repository's" \
  '[ $status -eq 0 ] && cmp -s "$S/drafts/t-cart.md" "$home/pending/t-cart.md" && cmp -s "$S/drafts/t-checkout.md" "$home/pending/t-checkout.md" && [ ! -e "$S/drafts.problems.md" ]' "$out"
printf -- '- https://github.com/acme/shop/issues/2 | draft: none\n' > "$S/tickets.md"; rm -rf "$S/drafts"
run materializing-drafts.sh
check "drafts refuses draft: none for a ticket of this project" '[ $status -eq 1 ] && grep -q "draft: none" "$S/drafts.problems.md"' "$out"

# --- handover and pin -------------------------------------------------------------------------

task handover; run materializing-handover.sh handover
check "handover passes at once on an empty diff" '[ $status -eq 0 ] && ! grep -q "handover.sh ran" <<<"$out"' "$out"
task pin; run materializing-handover.sh pin
check "pin passes at once on an empty diff" '[ $status -eq 0 ] && ! grep -q "pins.sh" <<<"$out"' "$out"
echo "- term" >> "$c/CONTEXT.md" && git -C "$c" commit -q -am "docs: a term"
task handover; run materializing-handover.sh handover
check "handover runs handover.sh on a change" '[ $status -eq 0 ] && grep -q "handover.sh ran" <<<"$out"' "$out"

# --- gates ------------------------------------------------------------------------------------

task gates; run materializing-gates.sh
check "gates passes a glossary change and says no gate command is configured" '[ $status -eq 0 ] && grep -q "no MATERIALIZING_GATES is set" <<<"$out"' "$out"
echo more >> "$c/src.txt" && git -C "$c" commit -q -am "a code change"
run materializing-gates.sh
check "gates refuses a change outside the allowed paths, into gates.problems.md" '[ $status -eq 1 ] && grep -q "src.txt" "$S/gates.problems.md"' "$out"
export MATERIALIZING_ALLOWED='CONTEXT.md src.txt' MATERIALIZING_GATES=true
run materializing-gates.sh
check "gates reads MATERIALIZING_GATES and MATERIALIZING_ALLOWED" '[ $status -eq 0 ] && grep -q "gates: true" <<<"$out"' "$out"
unset MATERIALIZING_ALLOWED MATERIALIZING_GATES
rm -f "$S/gates.problems.md"; task document; run materializing-gates.sh preview
check "gates preview runs in document and writes no problems file" '[ $status -eq 1 ] && [ ! -e "$S/gates.problems.md" ]' "$out"

echo
if [ "$failures" -eq 0 ]; then echo "all materializing template checks passed"; exit 0; fi
echo "$failures check(s) failed"; exit 1
