#!/usr/bin/env bash
# Offline test for the machine-keys gate: each case builds a throwaway tree holding the
# checked-in config and expected values, edits the config, and runs the gate through GATES_ROOT.
# Run: bash tests/machine-keys.test.sh
set -uo pipefail

here=$(cd "$(dirname "$0")/../scripts/gates" && pwd)
repo=$(cd "$here/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     /'; failures=$((failures + 1)); }

# setup <case>: a tree at $root with this checkout's expected values and its config as committed
# (HEAD, not the working copy, so a planted key in this checkout cannot bend the test).
setup() {
  root=$work/$1
  mkdir -p "$root/.spoolway" "$root/scripts/gates"
  cfg=$root/.spoolway/config.toml
  git -C "$repo" show HEAD:.spoolway/config.toml > "$cfg"
  cp "$here/machine-keys-expected.toml" "$root/scripts/gates/"
}

run() { GATES_ROOT=$root "$here/run.sh" machine-keys 2>&1; }

# expect <name> <GREEN|RED> <pattern that must appear>
expect() {
  local name=$1 want=$2 pat=$3 out code
  out=$(run); code=$?
  if [ "$want" = GREEN ] && [ "$code" -ne 0 ]; then fail "$name" "wanted GREEN, exit $code"$'\n'"$out"; return; fi
  if [ "$want" = RED ] && [ "$code" -ne 1 ]; then fail "$name" "wanted RED (exit 1), exit $code"$'\n'"$out"; return; fi
  if ! grep -q -E -- "$pat" <<<"$out"; then fail "$name" "no match for: $pat"$'\n'"$out"; return; fi
  pass "$name"
}

setup shipped
expect "the config as shipped is green, its header comments included" GREEN 'machine-keys/shipped-defaults'

setup ttl
sed -i 's/^prompt_cache_ttl = "5m"/prompt_cache_ttl = "1h"/' "$cfg"
expect "a changed prompt cache TTL is red" RED 'tracked: models\."claude-\*"\.prompt_cache_ttl = "1h"'
expect "the tracked TTL is named beside the changed one" RED 'shipped: models\."claude-\*"\.prompt_cache_ttl = "5m"'

# The diff once recorded: `spoolway sync` wrote the lane cap (and, then, the now-retired worktree root).
setup sync-345
sed -i '/^\[agents\.claude\]/a concurrency = 6' "$cfg"
expect "a lane cap is red" RED 'tracked: agents\.claude\.concurrency = 6'

setup prices
printf '\n[models."claude-opus-5"]\ninput = 5.0\noutput = 25.0\n' >> "$cfg"
expect "a price table is red" RED 'tracked: models\.claude-opus-5\.input = 5\.0'

setup dotted
printf '\n[models]\n"claude-opus-5".slots = 2\n' >> "$cfg"
expect "a dotted key under [models] is red" RED 'tracked: models\.claude-opus-5\.slots = 2'

setup root-dotted
sed -i '0,/^\[dispatch\]/s//agents.claude.concurrency = 6\n[dispatch]/' "$cfg"
expect "a dotted key before the first table is red" RED 'tracked: agents\.claude\.concurrency = 6'

setup inline
sed -i 's/^\[agents\.claude\]$/[agents]\nclaude = { kind = "claude", concurrency = 6 }\n[agents.other]/' "$cfg"
expect "an inline table carrying a lane cap is red" RED 'tracked: agents\.claude = \{.*concurrency = 6'

# Valid TOML spellings of the same keys that a bare-name match would miss.
setup quoted-table
printf '\n["agents".other]\nconcurrency = 6\n' >> "$cfg"
expect "a quoted table name is red" RED 'tracked: agents\.other\.concurrency = 6'

setup quoted-models
printf "\n['models'.x]\ninput = 5.0\n" >> "$cfg"
expect "a single-quoted table name is red" RED 'tracked: models\.x\.input = 5\.0'

setup spaced-dots
sed -i '0,/^\[dispatch\]/s//"agents" . claude . "concurrency" = 6\n[dispatch]/' "$cfg"
expect "a quoted, spaced dotted key is red" RED 'tracked: agents\.claude\.concurrency = 6'

# Same tree, same verdict, whatever the caller's locale: an invalid byte stops `.` in UTF-8.
setup locale
sed -i '/^\[agents\.claude\]/a concurrency = 6 # \xff' "$cfg"
for loc in C C.UTF-8; do
  out=$(LC_ALL=$loc GATES_ROOT=$root "$here/run.sh" machine-keys 2>&1); code=$?
  if [ "$code" -eq 1 ]; then pass "a lane cap beside an invalid byte is red under LC_ALL=$loc"
  else fail "a lane cap beside an invalid byte is red under LC_ALL=$loc" "exit $code"$'\n'"$out"; fi
done

# An unattended run and its cost ceiling are chosen when the dispatcher starts, per machine:
# never in the tracked config.
setup unattended-on
sed -i '/^\[unattended\]/,/^\[/s/^enabled = false/enabled = true/' "$cfg"
expect "unattended switched on in the tracked config is red" RED 'tracked: unattended\.enabled = true'

setup ceiling-dollars
sed -i 's/^max_cost_usd = 0\.0/max_cost_usd = 20.0/' "$cfg"
expect "a dollar ceiling in the tracked config is red" RED 'tracked: unattended\.max_cost_usd = 20\.0'
expect "the shipped ceiling is named beside the tracked one" RED 'shipped: unattended\.max_cost_usd = 0\.0'

setup ceiling-tokens
sed -i 's/^max_output_tokens = 0$/max_output_tokens = 2000000/' "$cfg"
expect "a token ceiling in the tracked config is red" RED 'tracked: unattended\.max_output_tokens = 2000000'

setup ceiling-inline
sed -i '0,/^\[dispatch\]/s//unattended = { enabled = true, max_cost_usd = 20.0 }\n[dispatch]/' "$cfg"
expect "an inline unattended table is red" RED 'tracked: unattended = \{'

# Who staffs `blocked` is the project's decision, not a machine's: it stays free to change.
setup staffing
sed -i 's/^blocked_model = .*/blocked_model = "some-other-model"/' "$cfg"
expect "the model that staffs blocked is not a machine-only key" GREEN 'machine-keys/shipped-defaults'

# Near misses that are not machine-only keys.
setup near-miss
printf '\n[models_extra]\nnote = 1\n\n[agents.other]\nkind = "concurrency"\n' >> "$cfg"
expect "a look-alike table and a value that says concurrency stay green" GREEN '4 machine-only keys'

# Nothing on either side still reports a row: a gate that dies silently leaves no evidence.
setup nothing
sed -i -e '/^prompt_cache_ttl = /d' -e '/^\[models\./d' \
  -e '/^\[unattended\]/,/^\[/{/^enabled = /d;/^max_output_tokens = /d;/^max_cost_usd = /d}' "$cfg"
echo '# no machine-only key ships' > "$root/scripts/gates/machine-keys-expected.toml"
expect "no key on either side reports a green row" GREEN '0 machine-only keys'

setup comment
sed -i 's/^prompt_cache_ttl = "5m"/  prompt_cache_ttl="5m"   # the provider cache TTL/' "$cfg"
expect "spacing and a trailing comment do not change a value" GREEN 'machine-keys/shipped-defaults'

setup removed
sed -i '/^prompt_cache_ttl = /d' "$cfg"
expect "a shipped key removed from the config is red" RED 'shipped: models\."claude-\*"\.prompt_cache_ttl = "5m"'

setup no-config
rm "$cfg"
expect "a missing config is red" RED 'machine-keys/config'

setup no-expected
rm "$root/scripts/gates/machine-keys-expected.toml"
expect "missing expected values are red" RED 'machine-keys/expected'

# The verdict depends only on the tree: a spoolway home full of overrides and a spoolway binary
# on PATH change nothing, and the binary is never run.
setup machine
mkdir -p "$work/home/.spoolway/proj/overrides" "$work/bin"
printf '[agents.claude]\nconcurrency = 6\n[models."claude-*"]\nprompt_cache_ttl = "1h"\n' \
  > "$work/home/.spoolway/proj/overrides/config.toml"
printf '#!/bin/sh\ntouch "%s/spoolway-was-run"\n' "$work" > "$work/bin/spoolway"
chmod +x "$work/bin/spoolway"
out=$(HOME=$work/home PATH=$work/bin:$PATH GATES_ROOT=$root "$here/run.sh" machine-keys 2>&1); code=$?
if [ "$code" -ne 0 ]; then fail "machine overrides do not reach the verdict" "exit $code"$'\n'"$out"
elif [ -e "$work/spoolway-was-run" ]; then fail "the gate never runs spoolway" "it ran the binary on PATH"
else pass "machine overrides and the installed binary do not reach the verdict"; fi

# The test trees are plain directories, so a green case also shows the gate needs no git history
# (CI checks out one commit). It needs no tool beyond the runner's either.
used=$(grep -v '^[[:space:]]*#' "$here/gates.d/machine-keys.sh" | grep -o -w -E 'awk|python3?|perl|diff' | sort -u | tr '\n' ' ')
if [ -n "$used" ]; then fail "the gate uses only sed, grep, sort and comm" "found: $used"
else pass "the gate uses no awk, python, perl or diff"; fi

if [ "$failures" -eq 0 ]; then echo "all passed"; else echo "$failures failed"; exit 1; fi
