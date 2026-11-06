#!/usr/bin/env bash
# Drives claude-plugin/spoolway/types.sh against a fixture plugin install and fixture consumers.
# Usage: tests/spoolway-types.test.sh (needs bash, git, jq and sha256sum)

set -u

repo="$(cd "$(dirname "$0")/.." && pwd)"
real="$repo/claude-plugin/spoolway"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

REV=6d82bbc6b8dc4e68e243add65576aae977229766
OTHER=1111111111111111111111111111111111111111

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1" "${3:-}"; fi; }

# --- The real tree --------------------------------------------------------------------------

if [ -d "$real/types" ]; then
  diff <(bash "$real/types.sh" manifest) "$real/types.manifest" >"$work/manifest.diff" 2>&1
  check "types.manifest is the manifest of types/" '[ $? -eq 0 ]' "$(head -5 "$work/manifest.diff"); regenerate it: bash claude-plugin/spoolway/types.sh manifest > claude-plugin/spoolway/types.manifest"
  check "no nested .spoolway/ under types/" '[ -z "$(find "$real/types" -name .spoolway)" ]'
  check "every pipeline the manifest ships sits in .spoolway/pipelines/" \
    '! cut -f2 "$real/types.manifest" | grep -E "\.yml$" | grep -vq "^\.spoolway/pipelines/"'
  if [ -f "$repo/.spoolway/types.subset" ]; then
    declared=$(grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$repo/.spoolway/types.subset" \
      | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | LC_ALL=C sort -u)
    unshipped=$(LC_ALL=C comm -23 <(printf '%s\n' "$declared") <(cut -f2 "$real/types.manifest" | LC_ALL=C sort))
    check "this repo's .spoolway/types.subset names only paths types.manifest ships" \
      '[ -n "$declared" ] && [ -z "$unshipped" ]' "$unshipped"
  fi
else
  fail "claude-plugin/spoolway/types/ exists"
fi

# --- Fixtures -------------------------------------------------------------------------------

# A plugin install: types.sh, a small types/ tree, its manifest, and the install record.
plugin="$work/cache/spoolway-companion/6d82bbc6b8dc-afc78acc"
config="$work/config"
make_plugin() {
  rm -rf "$plugin"
  mkdir -p "$plugin/spoolway/types/setup/pipelines" "$plugin/spoolway/types/setup/prompts/impl" \
    "$plugin/spoolway/types/setup/templates/tasks" "$plugin/spoolway/types/scripts/spoolway" "$config/plugins"
  cp "$real/types.sh" "$plugin/spoolway/types.sh"
  local t="$plugin/spoolway/types"
  printf 'version: "1.0"\nsteps: []\n' > "$t/setup/pipelines/dev.yml"
  printf 'Build it.\n' > "$t/setup/prompts/impl/PROMPT.md"
  ln -s impl "$t/setup/prompts/impl-spec"
  printf '# [[goal]]\n' > "$t/setup/templates/tasks/dev.md"
  printf '#!/usr/bin/env bash\necho lib\n' > "$t/scripts/spoolway/lib.sh"
  chmod +x "$t/scripts/spoolway/lib.sh"
  bash "$plugin/spoolway/types.sh" manifest > "$plugin/spoolway/types.manifest"
  installed "$REV"
}
installed() { # installed <gitCommitSha of the fixture install>
  jq -n --arg p "$plugin" --arg sha "$1" '{version: 2, plugins: {"spoolway-companion@spoolway-companion": [
    {scope: "project", projectPath: "/elsewhere", installPath: $p, version: "6d82bbc6b8dc-afc78acc", gitCommitSha: $sha}]}}' \
    > "$config/plugins/installed_plugins.json"
}

# A consumer checkout pinning the plugin at <sha>, with files of its own beside the setup.
consumer() { # consumer <name> <pinned sha>
  c="$work/$1"
  rm -rf "$c"
  mkdir -p "$c/.claude" "$c/.spoolway" "$c/scripts/spoolway"
  git -C "$c" init -q -b develop
  jq -n --arg sha "$2" '{extraKnownMarketplaces: {"spoolway-companion": {source: {source: "settings", name: "spoolway-companion", plugins: [
    {name: "other", source: {source: "git-subdir", url: "https://example.com/other.git", path: "claude-plugin", sha: "7c94c9bf2968f17deb496b285db0afdb610a01d9"}},
    {name: "spoolway-companion", source: {source: "git-subdir", url: "https://github.com/theTestTube/spoolway-companion.git", path: "claude-plugin", sha: $sha}}]}}}}' \
    > "$c/.claude/settings.json"
  printf '[dispatch]\nbackend = "herdr"\n' > "$c/.spoolway/config.toml"
  printf '#!/usr/bin/env bash\necho %s checks\n' "$1" > "$c/scripts/spoolway/checks.sh"
  commit "$c" init
}
commit() { git -C "$1" add -A && git -C "$1" -c user.email=t@t -c user.name=t commit -qm "$2"; }

run() { # run <consumer dir>
  out=$(CLAUDE_CONFIG_DIR="$config" bash "$plugin/spoolway/types.sh" write "$1" 2>&1)
  status=$?
}

# --- Refusals -------------------------------------------------------------------------------

make_plugin
consumer app "$REV"

jq 'del(.extraKnownMarketplaces)' "$c/.claude/settings.json" > "$work/s.json" && mv "$work/s.json" "$c/.claude/settings.json"
commit "$c" unpin
run "$c"
check "refuses a consumer that pins no spoolway-companion sha" '[ $status -ne 0 ] && grep -q "pins no spoolway-companion" <<<"$out"' "$out"
check "...and writes nothing" '[ ! -e "$c/.spoolway/plugin.lock" ] && [ -z "$(git -C "$c" status --porcelain)" ]'

consumer app "$OTHER"
run "$c"
check "refuses when the consumer pins another revision than this copy's" \
  '[ $status -ne 0 ] && grep -q "is revision 6d82bbc6b8dc and .* pins 111111111111" <<<"$out" && grep -q "claude plugin install spoolway-companion@spoolway-companion --scope project" <<<"$out"' "$out"
check "...and writes nothing" '[ -z "$(git -C "$c" status --porcelain)" ]'

consumer app "$REV"
mv "$config/plugins/installed_plugins.json" "$work/installed.bak"
run "$c"
check "refuses a copy with no install record (revision unknown)" '[ $status -ne 0 ] && grep -q "revision is unknown" <<<"$out"' "$out"
mv "$work/installed.bak" "$config/plugins/installed_plugins.json"

printf 'tampered\n' >> "$plugin/spoolway/types/setup/prompts/impl/PROMPT.md"
run "$c"
check "refuses a copy that does not match its own manifest" '[ $status -ne 0 ] && grep -q "does not match its own types.manifest" <<<"$out"' "$out"
check "...and writes nothing" '[ -z "$(git -C "$c" status --porcelain)" ]'
make_plugin

mkdir -p "$c/.spoolway/pipelines" && printf 'mine\n' > "$c/.spoolway/pipelines/dev.yml"
run "$c"
check "refuses when a path it would write has uncommitted changes" '[ $status -ne 0 ] && grep -q "uncommitted changes" <<<"$out" && grep -q "dev.yml" <<<"$out"' "$out"
check "...and leaves that file alone" '[ "$(cat "$c/.spoolway/pipelines/dev.yml")" = mine ]'
rm -rf "$c/.spoolway/pipelines"

# --- Writing --------------------------------------------------------------------------------

run "$c"
check "writes into a consumer pinned at this copy's revision" '[ $status -eq 0 ]' "$out"
check "the pipeline lands in .spoolway/pipelines/" 'cmp -s "$plugin/spoolway/types/setup/pipelines/dev.yml" "$c/.spoolway/pipelines/dev.yml"'
check "the task template lands in .spoolway/templates/tasks/" '[ -f "$c/.spoolway/templates/tasks/dev.md" ]'
check "a prompt symlink stays a symlink" '[ -L "$c/.spoolway/prompts/impl-spec" ] && [ "$(readlink "$c/.spoolway/prompts/impl-spec")" = impl ]'
check "a script lands in scripts/spoolway/ and stays executable" '[ -x "$c/scripts/spoolway/lib.sh" ]'
check "the consumer's own scripts and config are left alone" \
  '[ -z "$(git -C "$c" status --porcelain -- .spoolway/config.toml scripts/spoolway/checks.sh .claude)" ]'
check "the lock names the plugin and the pinned revision" \
  'grep -qx "plugin spoolway-companion" "$c/.spoolway/plugin.lock" && grep -qx "revision $REV" "$c/.spoolway/plugin.lock"'
check "the lock lists every path with its hash, as the manifest does" \
  '[ "$(grep -E "^[0-9]{6} " "$c/.spoolway/plugin.lock")" = "$(cat "$plugin/spoolway/types.manifest")" ]'

commit "$c" "take the types"
run "$c"
check "writing the same revision again changes nothing" '[ $status -eq 0 ] && [ -z "$(git -C "$c" status --porcelain)" ]' "$out"

# The same revision written into a second consumer: the same files, byte for byte.
first=$c
consumer backend "$REV"
run "$c"
check "a second consumer gets the same files and the same lock" \
  'diff -r --no-dereference "$first/.spoolway/prompts" "$c/.spoolway/prompts" >/dev/null && cmp -s "$first/.spoolway/plugin.lock" "$c/.spoolway/plugin.lock" && cmp -s "$first/scripts/spoolway/lib.sh" "$c/scripts/spoolway/lib.sh"'
check "...and keeps its own checks.sh" 'grep -q "backend checks" "$c/scripts/spoolway/checks.sh"'

# --- A consumer that takes a subset ---------------------------------------------------------

consumer sub "$REV"
printf '# only what this repo runs\n\n.spoolway/pipelines/dev.yml\nscripts/spoolway/lib.sh\n.spoolway/pipelines/dev.yml\n' \
  > "$c/.spoolway/types.subset"
commit "$c" "declare the subset"
run "$c"
check "a subset writes only the paths it names" \
  '[ $status -eq 0 ] && [ -f "$c/.spoolway/pipelines/dev.yml" ] && [ -x "$c/scripts/spoolway/lib.sh" ] && [ ! -e "$c/.spoolway/prompts/impl/PROMPT.md" ] && [ ! -e "$c/.spoolway/prompts/impl-spec" ] && [ ! -e "$c/.spoolway/templates/tasks/dev.md" ]' "$out"
taken=$(awk -F'\t' '$2 == ".spoolway/pipelines/dev.yml" || $2 == "scripts/spoolway/lib.sh"' \
  "$plugin/spoolway/types.manifest")
check "...and the lock lists only those, with their hashes, a repeat named once" \
  '[ "$(grep -E "^[0-9]{6} " "$c/.spoolway/plugin.lock")" = "$taken" ]'
check "...and says the take is a subset" 'grep -q "types.subset: 2 of 5 paths" <<<"$out"' "$out"
commit "$c" "take the subset"
run "$c"
check "writing the same subset again changes nothing" '[ $status -eq 0 ] && [ -z "$(git -C "$c" status --porcelain)" ]' "$out"

printf '# only what this repo runs\n\n.spoolway/pipelines/dev.yml\n' > "$c/.spoolway/types.subset"
run "$c"
check "a path the subset no longer names is deleted" \
  '[ $status -eq 0 ] && [ ! -e "$c/scripts/spoolway/lib.sh" ] && grep -q "deleted scripts/spoolway/lib.sh" <<<"$out"' "$out"
check "...the lock drops it too" '! grep -q "scripts/spoolway/lib.sh" "$c/.spoolway/plugin.lock"'
check "...and nothing else changes" \
  '[ "$(git -C "$c" status --porcelain | sort)" = "$(printf " D scripts/spoolway/lib.sh\n M .spoolway/plugin.lock\n M .spoolway/types.subset")" ]' "$(git -C "$c" status --porcelain)"

rm "$c/.spoolway/types.subset"
commit "$c" "take every type again"
run "$c"
check "without a subset every path is written again" \
  '[ $status -eq 0 ] && [ -f "$c/.spoolway/prompts/impl/PROMPT.md" ] && [ -f "$c/.spoolway/templates/tasks/dev.md" ] && [ -x "$c/scripts/spoolway/lib.sh" ]' "$out"
check "...and the lock lists the whole manifest" \
  '[ "$(grep -E "^[0-9]{6} " "$c/.spoolway/plugin.lock")" = "$(cat "$plugin/spoolway/types.manifest")" ]'

consumer bad "$REV"
printf '.spoolway/pipelines/nope.yml\n' > "$c/.spoolway/types.subset"
run "$c"
check "refuses a subset that names a path this revision does not ship" \
  '[ $status -ne 0 ] && grep -q "names paths this revision does not ship" <<<"$out" && grep -q "nope.yml" <<<"$out"' "$out"
check "...and writes nothing" \
  '[ ! -e "$c/.spoolway/plugin.lock" ] && [ -z "$(git -C "$c" status --porcelain -- .spoolway/pipelines .spoolway/prompts .spoolway/templates scripts/spoolway)" ]'

consumer empty "$REV"
printf '# nothing yet\n' > "$c/.spoolway/types.subset"
run "$c"
check "refuses a subset that names no paths" '[ $status -ne 0 ] && grep -q "names no paths" <<<"$out"' "$out"
check "...and writes nothing" \
  '[ ! -e "$c/.spoolway/plugin.lock" ] && [ -z "$(git -C "$c" status --porcelain -- .spoolway/pipelines .spoolway/prompts .spoolway/templates scripts/spoolway)" ]'

# A later revision that drops a path deletes it from the consumer, and only that path.
c=$first
NEXT=2222222222222222222222222222222222222222
rm "$plugin/spoolway/types/setup/templates/tasks/dev.md"
bash "$plugin/spoolway/types.sh" manifest > "$plugin/spoolway/types.manifest"
installed "$NEXT"
jq --arg sha "$NEXT" '(.extraKnownMarketplaces[].source.plugins[] | select(.name == "spoolway-companion") | .source.sha) = $sha' \
  "$c/.claude/settings.json" > "$work/s.json" && mv "$work/s.json" "$c/.claude/settings.json"
commit "$c" "bump the pin"
run "$c"
check "a path the new revision no longer ships is deleted" '[ $status -eq 0 ] && [ ! -e "$c/.spoolway/templates/tasks/dev.md" ] && grep -q "deleted .spoolway/templates/tasks/dev.md" <<<"$out"' "$out"
check "...the lock moves to the new revision" 'grep -qx "revision $NEXT" "$c/.spoolway/plugin.lock"'
check "...and nothing else changes" \
  '[ "$(git -C "$c" status --porcelain | sort)" = "$(printf " D .spoolway/templates/tasks/dev.md\n M .spoolway/plugin.lock")" ]' "$(git -C "$c" status --porcelain)"

# --- Usage ----------------------------------------------------------------------------------

out=$(bash "$real/types.sh" 2>&1); status=$?
check "no subcommand is a usage error (64)" '[ $status -eq 64 ]'

echo
if [ "$failures" -eq 0 ]; then echo "all passed"; else echo "$failures failure(s)"; exit 1; fi
