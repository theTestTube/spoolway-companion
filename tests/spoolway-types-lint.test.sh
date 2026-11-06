#!/usr/bin/env bash
# Offline lint over the canonical Spoolway types: the rules reviews kept
# enforcing by hand on every pipeline under claude-plugin/spoolway/types/setup/. Each rule is a
# function of a root directory, run on the real tree and again on a mutated copy that must fail.
# Usage: tests/spoolway-types-lint.test.sh (needs bash, grep, awk, cp)

set -u

unset "${!SPOOLWAY_@}"

repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1" "${3:-}"; fi; }

# --- The rules: each takes a root laid out like the repository and prints what it finds ------

# collect_last <root>: every pipeline has one step that goes to done, and it is collect.
collect_last() {
  local f ids
  for f in "$1"/claude-plugin/spoolway/types/setup/pipelines/*.yml; do
    ids=$(awk '/^  - id: / { cur = $3 } $1 == "on_pass:" && $2 == "done" { print cur }' "$f" | tr '\n' ' ')
    [ "$ids" = "collect " ] || echo "$f: the steps that end at done are '${ids% }', not collect"
  done
}

# base_literals <root>: a shared prompt or template names main or develop as its base.
base_literals() {
  local s="$1/claude-plugin/spoolway/types/setup"
  grep -rnEi 'base:[[:space:]`"]*(main|develop)([^A-Za-z0-9_-]|$)' "$s/prompts" "$s/templates" 2> /dev/null
}

# app_words <root>: an Architecting or Feeding-back prompt carries app-only words.
app_words() {
  local p="$1/claude-plugin/spoolway/types/setup/prompts"
  grep -rnEiw 'pnpm|expo|eas|sst|adb|sdk' "$p"/architecting-* "$p"/feeding-back-* 2> /dev/null
}

# closing_keywords <root>: a closing keyword before an issue reference, anywhere the types and
# the tests are. GitHub reads these even in a negated sentence.
closing_keywords() {
  grep -rnEi '\b(close[sd]?|fix(e[sd])?|resolve[sd]?)[: ]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?(#[0-9]+|https?://[^ ]+/issues/[0-9]+)' \
    "$1/claude-plugin/spoolway/types" "$1/tests" 2> /dev/null
}

# --- The real tree ---------------------------------------------------------------------------

check "every pipeline ends with collect" '[ -z "$(collect_last "$repo")" ]' "$(collect_last "$repo")"
check "no shared prompt or template names a base branch" '[ -z "$(base_literals "$repo")" ]' "$(base_literals "$repo")"
check "no Architecting or Feeding-back prompt carries app-only words" '[ -z "$(app_words "$repo")" ]' "$(app_words "$repo")"
check "no file writes a closing keyword before an issue" '[ -z "$(closing_keywords "$repo")" ]' "$(closing_keywords "$repo")"

# --- Mutations: a copy of the types and the tests, one rule broken at a time -------------------

mutant() { # mutant <name>: a fresh copy under $work/<name>, its path on stdout
  local d="$work/$1"
  mkdir -p "$d/claude-plugin/spoolway" "$d/tests"
  cp -r "$repo/claude-plugin/spoolway/types" "$d/claude-plugin/spoolway/types"
  echo "$d"
}
types_of() { echo "$1/claude-plugin/spoolway/types/setup"; }

m=$(mutant no-collect)
sed -i 's/^  - id: collect$/  - id: gather/' "$(types_of "$m")/pipelines/feeding-back.yml"
check "mutation: a pipeline without collect fails" '[ -n "$(collect_last "$m")" ]'

m=$(mutant collect-not-last)
sed -i '0,/on_pass: collect/s//on_pass: done/' "$(types_of "$m")/pipelines/architecting.yml"
check "mutation: a step other than collect going to done fails" '[ -n "$(collect_last "$m")" ]'

m=$(mutant base-main)
printf '  base: main\n' >> "$(types_of "$m")/templates/tasks/developing.md"
check "mutation: base: main in a template fails" '[ -n "$(base_literals "$m")" ]'

m=$(mutant base-develop)
printf -- '- `base: develop`, the same on every draft.\n' >> "$(types_of "$m")/prompts/materializing-tickets/PROMPT.md"
check "mutation: base: develop in a prompt fails" '[ -n "$(base_literals "$m")" ]'

for w in pnpm expo eas sst adb SDK; do
  for k in architecting-spec feeding-back-route; do
    m=$(mutant "word-$w-$k")
    printf 'Run %s before you start.\n' "$w" >> "$(types_of "$m")/prompts/$k/PROMPT.md"
    check "mutation: $w in $k fails" '[ -n "$(app_words "$m")" ]'
  done
done

m=$(mutant word-developing)
printf 'Run pnpm before you start.\n' >> "$(types_of "$m")/prompts/developing-implement/PROMPT.md"
check "a Developing prompt may carry app-only words" '[ -z "$(app_words "$m")" ]'

# Every keyword is built here, so that this file writes none before an issue itself.
kw=clo; fx=fi; rs=resol
n=0
for form in "${kw}ses #12" "${kw}sed example/app#12" "${kw}se: #12" "${fx}x #3" "${rs}ves https://github.com/o/r/issues/4"; do
  n=$((n + 1))
  m=$(mutant "kw-$n")
  printf 'This %s.\n' "$form" > "$(types_of "$m")/prompts/developing-report/closing.md"
  check "mutation: '$form' under types fails" '[ -n "$(closing_keywords "$m")" ]'
  rm "$(types_of "$m")/prompts/developing-report/closing.md"
  printf 'BODY="This %s."\n' "$form" > "$m/tests/fixture.test.sh"
  check "mutation: '$form' under tests fails" '[ -n "$(closing_keywords "$m")" ]'
done
m=$(mutant kw-clean)
printf 'part of #12, leaves #13 open, closes nothing.\n' > "$m/tests/clean.md"
check "part of and leaves open pass" '[ -z "$(closing_keywords "$m")" ]'

echo
if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
