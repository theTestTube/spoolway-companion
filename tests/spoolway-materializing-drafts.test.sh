#!/usr/bin/env bash
# Offline test for the `drafts` step of the shipped materializing-drafts.sh, on its refusal of
# machine-checkable acceptance criteria that cannot hold together. A throwaway consumer and a
# fake `spoolway`; nothing reaches GitHub or the network.
# Usage: tests/spoolway-materializing-drafts.test.sh (needs bash and git)

set -u

unset "${!SPOOLWAY_@}"

repo="$(cd "$(dirname "$0")/.." && pwd)"
shipped="$repo/claude-plugin/spoolway/types/scripts/spoolway"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1" "${3:-}"; fi; }

app=$work/shop
home=$work/home
scratch=$home/scratch/mat-demo
pending=$home/pending
mkdir -p "$app/scripts/spoolway" "$app/.spoolway" "$work/bin" "$home/queue"
cp "$shipped/materializing-drafts.sh" "$shipped/lib.sh" "$app/scripts/spoolway/"
printf 'MATERIALIZING_REPO=acme/shop\n' > "$app/.spoolway/companion.env"
git init -q -b main "$app"

# fake spoolway: refuses a document pinning FAKE_BAD_ID, naming the id, as the binary refuses an
# id that names a routine.
cat > "$work/bin/spoolway" <<'FAKE'
#!/bin/sh
dir=; while [ $# -gt 0 ]; do [ "$1" = "--from" ] && dir=$2; shift; done
if [ -n "${FAKE_BAD_ID:-}" ] && grep -rqsxF -- "id: $FAKE_BAD_ID" "$dir"; then
  echo "task id $FAKE_BAD_ID is the name of a routine. Give this task another id" >&2
  exit 1
fi
exit 0
FAKE
chmod +x "$work/bin/spoolway"

spec=https://github.com/acme/shop/issues/999
ticket=https://github.com/acme/shop/issues/501

# run <criteria> [VAR=value...]: one ticket whose draft carries the criteria. Sets $rc and $out.
run() {
  local criteria=$1; shift
  rm -rf "$scratch" "$pending"; mkdir -p "$scratch/drafts"
  printf -- '---\nid: mat-demo\ntitle: "docs(spec): materialize"\nstage: drafts\npipeline: materializing\nticket: %s\nclose_on_merge: false\n---\n## Context\n' "$spec" > "$home/queue/mat-demo.md"
  printf -- '- %s | draft: t501-one\n' "$ticket" > "$scratch/tickets.md"
  printf '## 1. feat(demo): build one\n- repos: shop\n' > "$scratch/breakdown.md"
  printf -- '---\nid: t501-one\ntitle: "feat(demo): build one"\ngroup: demo\ngroup_description: the demo\npipeline: developing\nticket: %s\nbase: main\n---\n## Context\npart of #999\n\n## Acceptance criteria\n%s\n' "$ticket" "$criteria" > "$scratch/drafts/t501-one.md"
  rc=0
  out=$(cd "$app" && env PATH="$work/bin:$PATH" SPOOLWAY_TASK=mat-demo SPOOLWAY_REPO="$app" SPOOLWAY_SCRATCH="$scratch" \
    SPOOLWAY_TASK_FILE="$home/queue/mat-demo.md" "$@" bash scripts/spoolway/materializing-drafts.sh 2>&1) || rc=$?
}
refused() { [ "$rc" -eq 1 ] && [ ! -e "$pending/t501-one.md" ] && case $out in *"$1"*) true ;; *) false ;; esac; }
passed() { [ "$rc" -eq 0 ] && [ -f "$pending/t501-one.md" ]; }

run $'- `config/routine.md` has `id: weekly`.\n- `config/routine.md` has `id: weekly-check`.'
check "two criteria pinning one key of one path differently are refused" "refused 'pins \`id:\` to both \"weekly\" and \"weekly-check\"'" "rc=$rc $out"

full='- `config/routine.md` has `id: weekly`, `group: weekly`, `pipeline: feeding-back`, `base: main`.'
run "$full" FAKE_BAD_ID=weekly
check "a criterion pinning a document the contract refuses is refused" "refused 'its acceptance criteria contradict the task contract'" "rc=$rc $out"

run "$full"
check "criteria that hold together pass" passed "rc=$rc $out"

run '- `spoolway task contract --from` accepts the routine.'
check "a criterion naming no path pins nothing" passed "rc=$rc $out"

printf '\n%s failure(s)\n' "$failures"
[ "$failures" -eq 0 ]
