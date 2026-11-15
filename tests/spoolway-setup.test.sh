#!/usr/bin/env bash
# Drives claude-plugin/skills/setup/setup.sh against throwaway consumers: an empty mono-repo, a
# multi-repo, a half-set-up consumer, one with another plugin's types, and a bump. `claude` is a
# stub that writes install records into a throwaway CLAUDE_CONFIG_DIR; `gh` is a fake that answers
# with the exact bytes the real one prints, and what it is asked to do is compared with cmp.
# Usage: tests/spoolway-setup.test.sh (needs bash, git, jq, sha256sum)

set -u

repo="$(cd "$(dirname "$0")/.." && pwd)"
setup="$repo/claude-plugin/skills/setup/setup.sh"
templates="$repo/claude-plugin/templates"
work="$(mktemp -d)"
[ -n "${KEEP:-}" ] || trap 'rm -rf "$work"' EXIT

REV=6d82bbc6b8dc4e68e243add65576aae977229766
NEW=2222222222222222222222222222222222222222
NEWER=3333333333333333333333333333333333333333
WIKI=4444444444444444444444444444444444444444

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1" "${3:-}"; fi; }

export HOME="$work/home"
mkdir -p "$HOME"
export CLAUDE_CONFIG_DIR="$work/config"
export STUB_SOURCES="$work/sources"
export STUB_DEFAULT="$repo/claude-plugin"
export GH_LOG="$work/gh.log"
export GH_LABELS="$work/labels"
mkdir -p "$work/bin" "$CLAUDE_CONFIG_DIR/plugins" "$STUB_SOURCES"
export PATH="$work/bin:$PATH"

# claude plugin install|update <plugin>@<marketplace> --scope project, run in the consumer: copies
# the pinned revision into the cache and records it for this project path, as Claude Code does.
# STUB_STALE=1 makes `update` a no-op, the stale per-path record a marketplace at the pin leaves.
cat > "$work/bin/claude" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = plugin ] || exit 2
verb=$2 id=$3 name=${3%@*} market=${3#*@}
echo "$verb $id $(pwd -P)" >> "$CLAUDE_CONFIG_DIR/claude.log"
[ "$verb" = update ] && [ -n "${STUB_STALE:-}" ] && exit 0
pin=$(jq -r --arg n "$name" '[.extraKnownMarketplaces[] | .source.plugins[]? | select(.name == $n) | .source.sha] | first' .claude/settings.json)
dst=$CLAUDE_CONFIG_DIR/plugins/cache/$market/$name/$pin
if [ ! -d "$dst" ]; then
  mkdir -p "$dst"
  if [ "$name" = spoolway-companion ]; then
    src=$STUB_SOURCES/$pin; [ -d "$src" ] || src=$STUB_DEFAULT
    cp -a "$src/." "$dst/"
  fi
fi
f=$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json
[ -f "$f" ] || echo '{"version":2,"plugins":{}}' > "$f"
jq --arg id "$id" --arg p "$(pwd -P)" --arg i "$dst" --arg s "$pin" '
  .plugins[$id] = ([(.plugins[$id] // [])[] | select(.projectPath != $p)]
    + [{scope: "project", projectPath: $p, installPath: $i, version: "0", gitCommitSha: $s}])' "$f" > "$f.new"
mv "$f.new" "$f"
STUB

# gh label list ... --jq '.[].name' prints one name per line and a final newline, as the real one;
# gh label create records its arguments, one call per line.
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
  "label list") cat "$GH_LABELS" ;;
  "label create") shift 2; printf '%s\n' "$*" >> "$GH_LOG" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 2 ;;
esac
STUB
chmod +x "$work/bin/claude" "$work/bin/gh"

# consumer <name>: a git repository with one commit and spoolway's own config.
consumer() {
  local c=$work/$1
  mkdir -p "$c/.spoolway"
  git -C "$c" init -q -b trunk
  printf '# %s\n' "$1" > "$c/README.md"
  printf '[dispatch]\nlane_quiet = "15m"\n' > "$c/.spoolway/config.toml"
  git -C "$c" add -A && git -C "$c" -c user.email=t@t -c user.name=t commit -q -m init
  printf '%s\n' "$c"
}
commit_all() { git -C "$1" add -A && git -C "$1" -c user.email=t@t -c user.name=t commit -q -m "$2"; }
# snapshot <dir>: a hash of every file and its mode outside .git, and the branch.
snapshot() {
  (cd "$1" && git rev-parse --abbrev-ref HEAD && find . -path ./.git -prune -o -type f -printf '%m %p\n' | LC_ALL=C sort \
    && find . -path ./.git -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum)
}
commits() { git -C "$1" rev-list --count HEAD; }
envval() { (cd "$1" && . "$repo/scripts/spoolway/lib.sh" && companion_env "$2"); }

# --- 1. an empty mono-repo ----------------------------------------------------------------

c=$(consumer mono)
cat > "$work/mono.answers" <<EOF
topology=mono
pipelines=developing architecting
issue_tracking=yes
project_key=acme/widgets
companion_sha=$REV
RUN_REPORT_REPO=acme/widgets
checks=bash tests/run.sh
EOF
printf '%s\n' 'PAGES_COMPILE_PATTERN=## \[[0-9-]*\] compile | ' >> "$work/mono.answers"

before=$(snapshot "$c")
out=$(bash "$setup" plan "$work/mono.answers" "$c" 2>&1); status=$?
check "plan writes nothing and stays on the branch" '[ $status -eq 0 ] && [ "$before" = "$(snapshot "$c")" ] && [ ! -e "$CLAUDE_CONFIG_DIR/claude.log" ]' "$out"
check "plan names what apply would write" 'grep -q "would: wrote docs/agents/projects.md" <<<"$out" && grep -q "would: install spoolway-companion@spoolway-companion" <<<"$out"' "$out"

out=$(bash "$setup" apply "$work/mono.answers" "$c" 2>&1); status=$?
check "apply passes" '[ $status -eq 0 ]' "$out"
check "apply works on a branch of its own and commits nothing" '[ "$(git -C "$c" rev-parse --abbrev-ref HEAD)" = spoolway-companion-setup ] && [ "$(commits "$c")" = 1 ]' "$(git -C "$c" rev-parse --abbrev-ref HEAD)"
check "projects.md is written for a mono-repo" 'grep -q "mono-repo" "$c/docs/agents/projects.md" && grep -q "acme/widgets" "$c/docs/agents/projects.md"'
check "the issue hook and its workflow are the templates, byte for byte" \
  'cmp -s "$c/.spoolway/hooks/github.sh" "$templates/setup/hooks/github.sh" && cmp -s "$c/.github/workflows/spoolway-issues.yml" "$templates/github/workflows/spoolway-issues.yml" && [ -x "$c/.spoolway/hooks/github.sh" ]'
check "config.toml gains issue_tracking, the rest kept" \
  'grep -qx "hook = \"github.sh\"" "$c/.spoolway/config.toml" && grep -qx "project_key = \"acme/widgets\"" "$c/.spoolway/config.toml" && grep -qx "lane_quiet = \"15m\"" "$c/.spoolway/config.toml"' "$(cat "$c/.spoolway/config.toml")"
check "companion.env reads back what was answered, a pattern with blanks included" \
  '[ "$(envval "$c" RUN_REPORT_REPO)" = acme/widgets ] && [ "$(envval "$c" PAGES_COMPILE_PATTERN)" = "## \[[0-9-]*\] compile | " ]' "$(cat "$c/.spoolway/companion.env")"
check "types.subset takes the chosen pipelines and not the others" \
  'grep -qx ".spoolway/pipelines/developing.yml" "$c/.spoolway/types.subset" && grep -qx ".spoolway/pipelines/architecting.yml" "$c/.spoolway/types.subset" && ! grep -q "^\.spoolway/.*\(feeding-back\|materializing\)" "$c/.spoolway/types.subset"'
check "the consumer scripts are written, executable, checks with the answered gate" \
  'for s in checks handover extra-worktree extra-handover extra-cleanup; do [ -x "$c/scripts/spoolway/$s.sh" ] || exit 1; done; sed -n "/# gates: begin/,/# gates: end/p" "$c/scripts/spoolway/checks.sh" | grep -qx "bash tests/run.sh"'
check "no materializing script is written for a consumer that does not take it" '[ -z "$(ls "$c/scripts/spoolway" | grep materializing)" ]'
check "settings pin the companion by sha and enable it" \
  '[ "$(jq -r ".extraKnownMarketplaces[\"spoolway-companion\"].source.plugins[0].source.sha" "$c/.claude/settings.json")" = $REV ] && jq -e ".enabledPlugins[\"spoolway-companion@spoolway-companion\"]" "$c/.claude/settings.json" >/dev/null'
check "the companion is installed for this project path" 'grep -qx "install spoolway-companion@spoolway-companion $c" "$CLAUDE_CONFIG_DIR/claude.log"'
check "the types are taken through types.sh write, only the subset's paths" \
  'grep -qx "plugin spoolway-companion" "$c/.spoolway/plugin.lock" && grep -qx "revision $REV" "$c/.spoolway/plugin.lock" && [ "$(grep -cE "^[0-9]{6} " "$c/.spoolway/plugin.lock")" = "$(grep -vc "^#" "$c/.spoolway/types.subset")" ] && [ -f "$c/.spoolway/pipelines/developing.yml" ] && [ ! -e "$c/.spoolway/pipelines/feeding-back.yml" ]' "$out"
check "a missing tracker doc is reported with the skill to run" 'grep -q "issue-tracker.md is missing; run /setup-matt-pocock-skills" <<<"$out" && grep -q "triage-labels.md is missing" <<<"$out"' "$out"

before=$(snapshot "$c")
out=$(bash "$setup" apply "$work/mono.answers" "$c" 2>&1); status=$?
check "a second apply changes nothing" '[ $status -eq 0 ] && [ "$before" = "$(snapshot "$c")" ] && grep -qx "nothing to add" <<<"$out"' "$out"

out=$(bash "$setup" detect "$c" 2>&1)
check "detect reads back what apply wrote" \
  'grep -qx "companion pin	$REV" <<<"$out" && grep -qx "old plugin	none" <<<"$out" && grep -qx "env FINDINGS_REPO	missing" <<<"$out" && grep -qx "file scripts/spoolway/checks.sh	present" <<<"$out"' "$out"

# --- labels ---------------------------------------------------------------------------------

printf 'bug\nspoolway:task\n' > "$GH_LABELS"
: > "$GH_LOG"
out=$(bash "$setup" labels acme/widgets 2>&1)
check "labels without --create only says what it would create" \
  '[ ! -s "$GH_LOG" ] && grep -qx "would create label spoolway:in-progress" <<<"$out" && grep -qx "kept label spoolway:task: present" <<<"$out"' "$out"
bash "$setup" labels acme/widgets --create > /dev/null 2>&1
printf '%s\n' "spoolway:in-progress -R acme/widgets --color 1D76DB --description spoolway: a task bound to this issue is queued or running" \
  "spoolway:review -R acme/widgets --color 5319E7 --description spoolway: the bound task handed over a pull request" > "$work/gh.expected"
check "labels --create creates only the missing ones, nothing else asked of gh" 'cmp -s "$GH_LOG" "$work/gh.expected"' "$(diff "$work/gh.expected" "$GH_LOG")"

# --- the pin -------------------------------------------------------------------------------

c=$(consumer nopin)
printf 'topology=mono\n' > "$work/nopin.answers"
before=$(snapshot "$c")
out=$(bash "$setup" apply "$work/nopin.answers" "$c" 2>&1); status=$?
check "no pin and no installed copy: apply refuses and writes nothing" \
  '[ $status -ne 0 ] && grep -q "no companion revision to pin" <<<"$out" && [ "$before" = "$(snapshot "$c")" ]' "$out"
printf 'topology=mono\ncompanion_sha=main\n' > "$work/nopin.answers"
out=$(bash "$setup" apply "$work/nopin.answers" "$c" 2>&1); status=$?
check "a pin that is no full sha is refused, nothing written" '[ $status -ne 0 ] && [ "$before" = "$(snapshot "$c")" ]' "$out"
own=$(jq -r --arg p "$work/mono" '.plugins["spoolway-companion@spoolway-companion"][] | select(.projectPath == $p) | .installPath' "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json")
printf 'topology=mono\n' > "$work/nopin.answers"
out=$(bash "$own/skills/setup/setup.sh" apply "$work/nopin.answers" "$c" 2>&1); status=$?
check "without companion_sha, the installed copy pins its own revision" \
  '[ $status -eq 0 ] && [ "$(jq -r ".extraKnownMarketplaces[\"spoolway-companion\"].source.plugins[0].source.sha" "$c/.claude/settings.json")" = $REV ]' "$out"

# --- 2. a multi-repo ------------------------------------------------------------------------

c=$(consumer multi)
cat > "$work/multi.answers" <<EOF
topology=multi
extra_repos=acme/api acme/infra
worktree_root=../worktrees
repos_rule=Name every repository the change touches, this one first.
issue_tracking=no
companion_sha=$REV
MATERIALIZING_REPO=acme/specs
EOF
out=$(bash "$setup" apply "$work/multi.answers" "$c" 2>&1); status=$?
check "multi: apply passes" '[ $status -eq 0 ]' "$out"
check "multi: projects.md lists the extra repositories, the rule and the worktree root" \
  'grep -q "acme/api" "$c/docs/agents/projects.md" && grep -q "acme/infra" "$c/docs/agents/projects.md" && grep -q "this one first" "$c/docs/agents/projects.md" && grep -q "../worktrees" "$c/docs/agents/projects.md" && grep -q "acme/specs" "$c/docs/agents/projects.md"'
check "multi: the extra-* templates are written, byte for byte and executable, and not named to do" \
  'for s in extra-worktree extra-handover extra-cleanup; do cmp -s "$c/scripts/spoolway/$s.sh" "$templates/scripts/spoolway/$s.sh" && [ -x "$c/scripts/spoolway/$s.sh" ] || exit 1; done; ! grep -q "to do: write scripts/spoolway/extra-" <<<"$out"' "$out"
check "multi: the extra repositories and their worktree root land in companion.env" \
  '[ "$(envval "$c" EXTRA_REPOS)" = "acme/api acme/infra" ] && [ "$(envval "$c" EXTRA_WORKTREE_ROOT)" = ../worktrees ]' "$(cat "$c/.spoolway/companion.env")"
check "multi: every pipeline is taken" '[ ! -e "$c/.spoolway/types.subset" ] && [ -f "$c/.spoolway/pipelines/materializing.yml" ]' "$out"
materializing_copied=1
for s in bind backing drafts gates handover; do
  f=scripts/spoolway/materializing-$s.sh
  { cmp -s "$c/$f" "$templates/$f" && [ -x "$c/$f" ] && grep -q "Written once by /spoolway-companion:setup" "$c/$f" && ! grep -q "to do: write $f" <<<"$out"; } || materializing_copied=
done
check "multi: the five materializing-* scripts are the templates, byte for byte, executable, and not named to do" '[ -n "$materializing_copied" ]' "$out"
printf 'topology=multi\ncompanion_sha=%s\n' "$REV" > "$work/multi-bare.answers"
out=$(bash "$setup" apply "$work/multi-bare.answers" "$(consumer multi-bare)" 2>&1)
check "multi: without extra_repos or worktree_root, both keys are named to do" \
  'grep -q "to do: topology is multi and extra_repos is empty" <<<"$out" && grep -q "to do: topology is multi and worktree_root is empty" <<<"$out"' "$out"
check "multi: no issue hook without issue tracking" '[ ! -e "$c/.spoolway/hooks/github.sh" ] && ! grep -q issue_tracking "$c/.spoolway/config.toml"'
check "multi: MATERIALIZING_REPO lands in companion.env" '[ "$(envval "$c" MATERIALIZING_REPO)" = acme/specs ]'

# --- 3. a half-set-up consumer --------------------------------------------------------------

c=$(consumer half)
mkdir -p "$c/scripts/spoolway" "$c/.claude"
printf 'RUN_REPORT_REPO=acme/old\nPAGES_DIR=pages\n' > "$c/.spoolway/companion.env"
printf '#!/usr/bin/env bash\n# gates: begin\nmake test\n# gates: end\n' > "$c/scripts/spoolway/checks.sh"
printf '[issue_tracking]\nhook = "other.sh"\n' >> "$c/.spoolway/config.toml"
printf '.spoolway/pipelines/developing.yml\n' > "$c/.spoolway/types.subset"
printf '{"extraKnownMarketplaces": {"tools": {"source": {"source": "settings", "name": "tools", "plugins": [{"name": "lint", "source": {"source": "git-subdir", "url": "https://example.com/lint.git", "path": "claude-plugin", "sha": "%s"}}]}}}}\n' "$WIKI" > "$c/.claude/settings.json"
commit_all "$c" half
cp -a "$c" "$work/half.before"
cat > "$work/half.answers" <<EOF
topology=mono
pipelines=developing
issue_tracking=yes
project_key=acme/half
companion_sha=$REV
RUN_REPORT_REPO=acme/new
FINDINGS_REPO=acme/findings
EOF
out=$(bash "$setup" apply "$work/half.answers" "$c" 2>&1); status=$?
check "half: apply passes" '[ $status -eq 0 ]' "$out"
check "half: a present consumer script is kept byte for byte" 'cmp -s "$c/scripts/spoolway/checks.sh" "$work/half.before/scripts/spoolway/checks.sh" && grep -q "kept scripts/spoolway/checks.sh: present" <<<"$out"' "$out"
check "half: companion.env keeps its lines, appends the missing key, reports the differing one" \
  '[ "$(head -2 "$c/.spoolway/companion.env")" = "$(cat "$work/half.before/.spoolway/companion.env")" ] && [ "$(envval "$c" RUN_REPORT_REPO)" = acme/old ] && [ "$(envval "$c" FINDINGS_REPO)" = acme/findings ] && grep -q "RUN_REPORT_REPO: it is \"acme/old\", the answer was \"acme/new\"" <<<"$out"' "$(cat "$c/.spoolway/companion.env")"
check "half: config.toml keeps the hook it has and gains project_key under the same section" \
  'grep -qx "hook = \"other.sh\"" "$c/.spoolway/config.toml" && ! grep -q "github.sh" "$c/.spoolway/config.toml" && [ "$(sed -n "/^\[issue_tracking\]/,\$p" "$c/.spoolway/config.toml" | grep -c "project_key = \"acme/half\"")" = 1 ] && grep -q "it is \"other.sh\"" <<<"$out"' "$(cat "$c/.spoolway/config.toml")"
check "half: an existing types.subset is kept" 'cmp -s "$c/.spoolway/types.subset" "$work/half.before/.spoolway/types.subset" && grep -q "kept .spoolway/types.subset: present" <<<"$out"' "$out"
check "half: the other plugin's entry is unchanged and the companion's is added beside it" \
  '[ "$(jq -S ".extraKnownMarketplaces.tools" "$c/.claude/settings.json")" = "$(jq -S ".extraKnownMarketplaces.tools" "$work/half.before/.claude/settings.json")" ] && [ -n "$(jq -r ".extraKnownMarketplaces[\"spoolway-companion\"].source.plugins[0].source.sha" "$c/.claude/settings.json")" ]'

# --- 4. a consumer whose types another plugin owns -------------------------------------------

c=$(consumer legacy)
mkdir -p "$c/scripts/gates" "$c/.claude" "$c/.spoolway/pipelines"
printf '# Written by /legacy-harness:spoolway-types\nplugin legacy-harness\nrevision %s\n100644 %s\t.spoolway/pipelines/developing.yml\n' "$WIKI" "$WIKI" > "$c/.spoolway/plugin.lock"
printf 'steps: []\n' > "$c/.spoolway/pipelines/developing.yml"
printf '#!/usr/bin/env bash\nPLUGIN_LOCK_TAKE=/legacy-harness:spoolway-types\n' > "$c/scripts/gates/lock.sh"
printf '{\n  "extraKnownMarketplaces": {\n    "tools": {\n      "source": {"source": "settings", "name": "tools", "plugins": [{"name": "legacy-harness", "source": {"source": "git-subdir", "url": "https://example.com/legacy.git", "path": "claude-plugin", "sha": "%s"}}]}\n    }\n  },\n  "enabledPlugins": {"legacy-harness@tools": true}\n}\n' "$WIKI" > "$c/.claude/settings.json"
commit_all "$c" legacy
cp -a "$c" "$work/legacy.before"
cat > "$work/legacy.answers" <<EOF
topology=mono
pipelines=developing
companion_sha=$REV
EOF
out=$(bash "$setup" detect "$c" 2>&1)
check "legacy: detect names the other plugin" 'grep -qx "old plugin	legacy-harness" <<<"$out"' "$out"
out=$(bash "$setup" apply "$work/legacy.answers" "$c" 2>&1); status=$?
check "legacy: apply passes and reports the other plugin" '[ $status -eq 0 ] && grep -q "found the legacy-harness plugin" <<<"$out"' "$out"
check "legacy: its lock, its gate and its pipeline are untouched" \
  'cmp -s "$c/.spoolway/plugin.lock" "$work/legacy.before/.spoolway/plugin.lock" && cmp -s "$c/scripts/gates/lock.sh" "$work/legacy.before/scripts/gates/lock.sh" && cmp -s "$c/.spoolway/pipelines/developing.yml" "$work/legacy.before/.spoolway/pipelines/developing.yml" && [ ! -e "$c/.spoolway/types.subset" ]'
check "legacy: its settings entry is unchanged, the companion is added and installed beside it" \
  '[ "$(jq -S "{t: .extraKnownMarketplaces.tools, e: .enabledPlugins[\"legacy-harness@tools\"]}" "$c/.claude/settings.json")" = "$(jq -S "{t: .extraKnownMarketplaces.tools, e: .enabledPlugins[\"legacy-harness@tools\"]}" "$work/legacy.before/.claude/settings.json")" ] && grep -qx "install spoolway-companion@spoolway-companion $c" "$CLAUDE_CONFIG_DIR/claude.log"'

# --- 5. a bump ------------------------------------------------------------------------------

c=$work/mono
commit_all "$c" "take the companion"
rm "$c/scripts/spoolway/handover.sh"; commit_all "$c" "drop a script"
# The settings as a person formats them, not as jq would: four-space indent, keys out of order.
jq --indent 4 '{enabledPlugins, extraKnownMarketplaces}' "$c/.claude/settings.json" | sed 's/": /" :  /' > "$c/.claude/settings.json.new" && mv "$c/.claude/settings.json.new" "$c/.claude/settings.json"
# A consumer that took Materializing holds its scripts; the bump diffs what it copied.
cp -p "$templates/scripts/spoolway/materializing-drafts.sh" "$c/scripts/spoolway/"
commit_all "$c" "format"
cp -a "$repo/claude-plugin" "$STUB_SOURCES/$NEW"
printf '# a line the new revision adds\n' >> "$STUB_SOURCES/$NEW/templates/setup/hooks/github.sh"
printf '# a line the new revision adds to drafts\n' >> "$STUB_SOURCES/$NEW/templates/scripts/spoolway/materializing-drafts.sh"
cp "$c/.spoolway/hooks/github.sh" "$work/github.sh.before"

out=$(bash "$setup" bump "$NEW" "$c" 2>&1); status=$?
check "bump passes" '[ $status -eq 0 ]' "$out"
check "bump moves only the companion's sha, in place" \
  '[ "$(wc -l < "$c/.claude/settings.json")" -gt 10 ] && grep -q "$NEW" "$c/.claude/settings.json" && cmp -s <(sed "s/$NEW/$REV/" "$c/.claude/settings.json") <(git -C "$c" show HEAD:.claude/settings.json)' "$(git -C "$c" diff -- .claude/settings.json)"
check "bump updates the install for this project path" 'grep -qx "update spoolway-companion@spoolway-companion $c" "$CLAUDE_CONFIG_DIR/claude.log"'
check "bump retakes the types and the lock" 'grep -qx "revision $NEW" "$c/.spoolway/plugin.lock"' "$out"
check "bump writes back a missing consumer script" '[ -x "$c/scripts/spoolway/handover.sh" ]' "$out"
check "bump prints the template's change and leaves the consumer's copy alone" \
  'grep -q "^+# a line the new revision adds" <<<"$out" && grep -q "template setup/hooks/github.sh changed upstream" <<<"$out" && cmp -s "$c/.spoolway/hooks/github.sh" "$work/github.sh.before"' "$out"
check "bump prints a materializing template's change" \
  'grep -q "^+# a line the new revision adds to drafts" <<<"$out" && grep -q "scripts/spoolway/materializing-drafts.sh" <<<"$out"' "$out"
check "bump works on its own branch and commits nothing" '[ "$(git -C "$c" rev-parse --abbrev-ref HEAD)" = spoolway-companion-${NEW:0:12} ] && [ -n "$(git -C "$c" status --porcelain)" ] && [ "$(git -C "$c" log -1 --format=%s)" = format ]'

commit_all "$c" "bumped"
lock_before=$(cat "$c/.spoolway/plugin.lock")
cp -a "$repo/claude-plugin" "$STUB_SOURCES/$NEWER"
out=$(STUB_STALE=1 bash "$setup" bump "$NEWER" "$c" 2>&1); status=$?
check "a stale per-path record is reported and the types are not retaken" \
  '[ $status -eq 0 ] && grep -q "after update, the pin is ${NEWER:0:12}" <<<"$out" && [ "$lock_before" = "$(cat "$c/.spoolway/plugin.lock")" ]' "$out"

# --- 7. memex: the machine's config and index timer -----------------------------------------
# `memex` and `systemctl` are stubs and HOME is a throwaway one: nothing here touches the real
# index, the real config or the real user manager.

export MEMEX_LOG="$work/memex.log"
cat > "$work/bin/memex" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *--version*) echo "memex 0.0.0-stub" ;;
  "index stats"*) printf 'index: x\ndocuments: 80000\nvectors: %s (dims 768, model gemma)\n' "${MEMEX_VECTORS:-14775}" ;;
  "daemon enable"*)
    echo "$*" >> "$MEMEX_LOG"
    [ -f "$HOME/.config/systemd/user/memex-index.timer.d/boot-only.conf" ] && echo "boot-only drop-in was on disk" >> "$MEMEX_LOG"
    u=$HOME/.config/systemd/user; cfg=$HOME/.memex/config.toml
    mkdir -p "$u" "$HOME/.memex"
    printf '[Service]\nExecStart=/x/memex index\n' > "$u/memex-index.service"
    printf '[Timer]\nOnBootSec=5min\nOnUnitActiveSec=3600s\n' > "$u/memex-index.timer"
    grep -qs '^auto_index_on_search' "$cfg" || { printf '# Background indexing handles freshness.\nauto_index_on_search = false\n\n'; cat "$cfg" 2> /dev/null || true; } > "$cfg.tmp"
    [ -f "$cfg.tmp" ] && mv "$cfg.tmp" "$cfg"
    printf 'index_service_mode = "interval"\nindex_service_interval = 3600\n' >> "$cfg" ;;
  *) echo "fake memex: unexpected $*" >&2; exit 2 ;;
esac
STUB
cat > "$work/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
echo "systemctl $*" >> "$MEMEX_LOG"
if [ "$*" = "--user show-environment" ] && [ -n "${STUB_FASTEMBED:-}" ]; then echo "FASTEMBED_CACHE_DIR=$STUB_FASTEMBED"; fi
exit 0
STUB
chmod +x "$work/bin/memex" "$work/bin/systemctl"
hsnap() { (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum); }
mhome() { local h=$work/home-$1; rm -rf "$h"; mkdir -p "$h/.memex/index"; printf '%s\n' "$h"; }
msetup() { HOME=$1 bash "$setup" memex "$2" "$3" 2>&1; }
mcfgval() { grep -E "^$2 *=" "$1/.memex/config.toml" | tail -n 1 | cut -d= -f2- | tr -d ' "'; }

printf 'memex_schedule=boot\nmemex_auto_index_on_search=false\n' > "$work/memex-boot.answers"
export STUB_FASTEMBED=/cache
h=$(mhome boot)
before=$(hsnap "$h"); : > "$MEMEX_LOG"
out=$(msetup "$h" plan "$work/memex-boot.answers"); status=$?
check "memex plan writes nothing and starts nothing" '[ $status -eq 0 ] && [ "$before" = "$(hsnap "$h")" ] && ! grep -q "daemon enable" "$MEMEX_LOG"' "$out"
check "memex plan names the config keys, both drop-ins and the daemon call" \
  'grep -q "would: added embeddings = \"local\" to $h/.memex/config.toml" <<<"$out" && grep -q "would: added auto_index_on_search = false" <<<"$out" && grep -q "would: wrote $h/.config/systemd/user/memex-index.service.d/limits.conf" <<<"$out" && grep -q "would: wrote $h/.config/systemd/user/memex-index.timer.d/boot-only.conf" <<<"$out" && grep -q "would: ran memex daemon enable" <<<"$out"' "$out"

: > "$MEMEX_LOG"
out=$(msetup "$h" apply "$work/memex-boot.answers"); status=$?
check "memex apply: embeddings on, auto-index off, timer installed once" \
  '[ $status -eq 0 ] && [ "$(mcfgval "$h" embeddings)" = local ] && [ "$(mcfgval "$h" auto_index_on_search)" = false ] && [ "$(grep -c "^daemon enable --interval 3600" "$MEMEX_LOG")" = 1 ]' "$out"
check "memex apply: the 3-minute drop-in resets the hourly lines, the limits drop-in is written" \
  'grep -qx "OnStartupSec=3min" "$h/.config/systemd/user/memex-index.timer.d/boot-only.conf" && grep -qx "OnUnitActiveSec=" "$h/.config/systemd/user/memex-index.timer.d/boot-only.conf" && grep -qx "MemoryHigh=2500M" "$h/.config/systemd/user/memex-index.service.d/limits.conf"' "$out"
check "memex apply: the drop-in is on disk before the daemon call, which loads it with its one restart" \
  'grep -qx "boot-only drop-in was on disk" "$MEMEX_LOG"' "$(cat "$MEMEX_LOG")"
check "memex apply: nothing leaks into a consumer's companion.env or the checkout" '! grep -q "memex" <<<"$(cat "$work/mono/.spoolway/companion.env" 2>/dev/null)"'
out=$(HOME=$h bash "$setup" detect "$work/mono" 2>&1)
check "detect reads the memex facts back" \
  'grep -qx "memex schedule	boot" <<<"$out" && grep -qx "memex embeddings	local" <<<"$out" && grep -qx "memex auto_index_on_search	false" <<<"$out" && grep -qx "memex limits drop-in	present" <<<"$out" && grep -qx "memex vectors	14775" <<<"$out"' "$out"

before=$(hsnap "$h"); : > "$MEMEX_LOG"
out=$(msetup "$h" apply "$work/memex-boot.answers"); status=$?
check "a second memex apply changes nothing and does not call the daemon again" \
  '[ $status -eq 0 ] && [ "$before" = "$(hsnap "$h")" ] && ! grep -q "daemon enable" "$MEMEX_LOG" && grep -qx "nothing to add" <<<"$out"' "$out"

printf 'memex_schedule=hourly\nmemex_auto_index_on_search=true\n' > "$work/memex-hourly.answers"
h=$(mhome hourly); : > "$MEMEX_LOG"
out=$(msetup "$h" apply "$work/memex-hourly.answers"); status=$?
check "hourly: no 3-minute drop-in, the limits drop-in, and auto-index true survives the daemon call" \
  '[ $status -eq 0 ] && [ ! -e "$h/.config/systemd/user/memex-index.timer.d/boot-only.conf" ] && [ -f "$h/.config/systemd/user/memex-index.service.d/limits.conf" ] && [ "$(mcfgval "$h" auto_index_on_search)" = true ] && [ "$(HOME=$h bash "$setup" detect "$work/mono" | grep "^memex schedule")" = "memex schedule	hourly" ]' "$out"
out=$(msetup "$h" apply "$work/memex-boot.answers")
check "a different answer than the timer on disk is reported and the timer is kept" \
  'grep -q "kept the memex-index timer as it is (hourly), the answer was boot" <<<"$out" && [ "$(mcfgval "$h" auto_index_on_search)" = true ] && grep -q "kept $h/.memex/config.toml auto_index_on_search: it is \"true\", the answer was \"false\"" <<<"$out"' "$out"

h=$(mhome low); : > "$MEMEX_LOG"
out=$(MEMEX_VECTORS=128 msetup "$h" apply "$work/memex-boot.answers"); status=$?
check "an index with almost no vectors gets no timer: the backfill is to do by hand first" \
  '[ $status -eq 0 ] && grep -q "to do: the index holds 128 vectors" <<<"$out" && [ ! -e "$h/.config/systemd/user/memex-index.timer" ] && ! grep -q "daemon enable" "$MEMEX_LOG" && [ "$(mcfgval "$h" embeddings)" = local ]' "$out"

h=$(mhome off); mkdir -p "$h/.memex"; printf 'embeddings = false\n[ui]\ntheme = "dark"\n' > "$h/.memex/config.toml"
out=$(msetup "$h" apply "$work/memex-boot.answers")
check "embeddings = false is reported, kept, and the tables below it stay intact" \
  'grep -q "to do: $h/.memex/config.toml embeddings is \"false\"" <<<"$out" && [ "$(mcfgval "$h" embeddings)" = false ] && grep -qx "theme = \"dark\"" "$h/.memex/config.toml"' "$out"

printf 'memex_schedule=none\nmemex_auto_index_on_search=true\n' > "$work/memex-none.answers"
printf 'memex_schedule=none\n' > "$work/memex-none2.answers"
h=$(mhome none); out=$(msetup "$h" apply "$work/memex-none.answers")
check "no schedule: nothing installed, auto-index set as answered, the manual command named" \
  '[ ! -e "$h/.config/systemd/user" ] && [ "$(mcfgval "$h" auto_index_on_search)" = true ] && grep -q "no memex schedule: run .memex index embed. by hand" <<<"$out"' "$out"
msetup "$(mhome keep)" apply "$work/memex-boot.answers" > /dev/null; h=$work/home-keep
out=$(msetup "$h" apply "$work/memex-none2.answers")
check "no schedule on a machine that has one: reported and kept, never removed" 'grep -q "kept the memex-index timer (boot)" <<<"$out" && [ -f "$h/.config/systemd/user/memex-index.timer" ]' "$out"

out=$(PATH=/usr/bin:/bin HOME=$(mhome nomemex) bash "$setup" memex apply "$work/memex-boot.answers" 2>&1); status=$?
check "no memex on PATH: a to do line, no failure" '[ $status -eq 0 ] && grep -q "to do: memex is not on PATH" <<<"$out"' "$out"
printf 'memex_schedule=daily\n' > "$work/memex-bad.answers"
out=$(msetup "$(mhome bad)" apply "$work/memex-bad.answers"); status=$?
check "a schedule that is none, hourly or boot only" '[ $status -ne 0 ] && grep -q "none, hourly or boot" <<<"$out"' "$out"

unset STUB_FASTEMBED
out=$(msetup "$(mhome nocache)" apply "$work/memex-boot.answers")
check "a user manager without FASTEMBED_CACHE_DIR is named to do" 'grep -q "to do: FASTEMBED_CACHE_DIR is not in the systemd user environment" <<<"$out"' "$out"

c=$(consumer withmemex)
printf 'topology=mono\ncompanion_sha=%s\nmemex_schedule=boot\nmemex_auto_index_on_search=false\n' "$REV" > "$work/withmemex.answers"
out=$(bash "$setup" apply "$work/withmemex.answers" "$c" 2>&1)
check "the consumer apply ignores the memex keys: none reaches companion.env, none is written for the machine" \
  '! grep -qi memex "$c/.spoolway/companion.env" 2>/dev/null && [ ! -e "$HOME/.memex/config.toml" ] && [ ! -e "$HOME/.config/systemd" ]' "$out"

# --- the content rule -----------------------------------------------------------------------

check "no project-specific name in the skill, its templates or this suite" \
  '! grep -rniE "i[- ]?ching" "$repo/claude-plugin/skills/setup" "$templates" "$repo/tests/spoolway-setup.test.sh"'

echo
[ $failures -eq 0 ] && echo "all passed" || echo "$failures failed"
[ $failures -eq 0 ]
