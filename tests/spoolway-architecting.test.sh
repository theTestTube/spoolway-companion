#!/usr/bin/env bash
# Offline test for the Architecting pipeline type: the canonical definitions
# under claude-plugin/spoolway/types/ are written into a throwaway consumer, as
# tests/spoolway-types.test.sh does, and the real `spoolway pipeline check` runs there under a
# throwaway HOME, since checks.sh validates only this repository's own .spoolway/ (a copy at an
# older pin). Nothing reaches GitHub, and spoolway never runs with the real HOME.
# Usage: tests/spoolway-architecting.test.sh (needs bash, git, jq, sha256sum and spoolway)

set -u

repo="$(cd "$(dirname "$0")/.." && pwd)"
real="$repo/claude-plugin/spoolway"
types="$real/types/setup"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

REV=6d82bbc6b8dc4e68e243add65576aae977229766

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1" "${3:-}"; fi; }

# --- The definitions ------------------------------------------------------------------------

p="$types/pipelines/architecting.yml"
check "architecting.yml exists" '[ -f "$p" ]'

# step_value <step id> <key>: one key of one step of the pipeline file.
step_value() {
  awk -v id="$1" -v key="$2" '
    /^  - id: / { cur = $3; next }
    cur == id && $1 == key ":" { sub(/^[^:]*:[ \t]*/, ""); print; exit }' "$p"
}
check "the steps are recall, chart, resolve, spec, report, artifact, collect, in order" \
  '[ "$(grep -E "^  - id: " "$p" | awk "{print \$3}" | tr "\n" " ")" = "recall chart resolve spec report artifact collect " ]'

# mode_steps <skip_steps>: the steps a task runs, following on_pass from recall and passing at once
# through each step its skip_steps names (the lane's prompt does the passing).
mode_steps() {
  local cur=recall out=""
  while [ "$cur" != done ]; do
    case " $1 " in *" $cur "*) ;; *) out="$out$cur " ;; esac
    cur=$(step_value "$cur" on_pass)
  done
  printf '%s' "$out"
}
check "chart mode (skip_steps: [resolve, spec]) runs recall, chart, report, artifact, collect" \
  '[ "$(mode_steps "resolve spec")" = "recall chart report artifact collect " ]'
check "resolve mode (skip_steps: [chart, spec, artifact]) runs recall, resolve, report, collect" \
  '[ "$(mode_steps "chart spec artifact")" = "recall resolve report collect " ]'
check "spec mode (skip_steps: [recall, chart, resolve]) runs spec, report, artifact, collect" \
  '[ "$(mode_steps "recall chart resolve")" = "spec report artifact collect " ]'
check "recall runs on Haiku" '[ "$(step_value recall model)" = claude-haiku-5-5 ]'
check "spec runs on Sonnet" '[ "$(step_value spec model)" = claude-sonnet-5-5 ]'
for s in chart resolve report; do
  check "$s runs on Opus" '[ "$(step_value $s model)" = claude-opus-5-5 ]'
done
for s in recall chart resolve spec report; do
  check "$s runs the prompt architecting-$s" '[ "$(step_value $s prompt)" = "architecting-$s" ]'
  check "the prompt architecting-$s exists" '[ -s "$types/prompts/architecting-$s/PROMPT.md" ]'
done
check "effort is high on recall" '[ "$(step_value recall effort)" = high ]'
check "effort is medium on chart" '[ "$(step_value chart effort)" = medium ]'
check "effort is medium on resolve" '[ "$(step_value resolve effort)" = medium ]'
check "effort is medium on spec" '[ "$(step_value spec effort)" = medium ]'
check "effort is high on report" '[ "$(step_value report effort)" = high ]'
check "artifact runs Sonnet at high effort, the prompt architecting-artifact, between report and collect" \
  '[ "$(step_value artifact model)" = claude-sonnet-5-5 ] && [ "$(step_value artifact effort)" = high ] && [ "$(step_value artifact prompt)" = architecting-artifact ] && [ "$(step_value report on_pass)" = artifact ] && [ "$(step_value artifact on_pass)" = collect ] && [ -s "$types/prompts/architecting-artifact/PROMPT.md" ]'
check "chart and resolve run wayfinder and spec runs to-spec and report runs retro" \
  '[ "$(step_value chart skills)" = mattpocock-skills:wayfinder ] && [ "$(step_value resolve skills)" = mattpocock-skills:wayfinder ] && [ "$(step_value spec skills)" = mattpocock-skills:to-spec ] && [ "$(step_value report skills)" = mattpocock-skills:retro ]'
check "there is no handover or pin step, so no pull request" '! grep -qE "^  - id: (handover|pin)" "$p"'
check "collect is the last step before done" \
  '[ "$(step_value collect run)" = "scripts/spoolway/collect.sh --keep-days 90" ] && [ "$(step_value artifact on_pass)" = collect ] && [ "$(step_value collect on_pass)" = done ]'
check "the task template exists" '[ -s "$types/templates/tasks/architecting.md" ]'
for f in pipelines/architecting.yml prompts/architecting-recall/PROMPT.md prompts/architecting-chart/PROMPT.md \
  prompts/architecting-resolve/PROMPT.md prompts/architecting-spec/PROMPT.md prompts/architecting-report/PROMPT.md prompts/architecting-artifact/PROMPT.md templates/tasks/architecting.md; do
  check "types.manifest lists .spoolway/$f" 'cut -f2 "$real/types.manifest" | grep -qxF ".spoolway/$f"'
done
check "the template names a draft's own id and group, and why two drafts may not share a group" \
  'grep -qF "id: <the drafted task" "$types/templates/tasks/architecting.md" && grep -qF "group: <the chain the drafted task is on>" "$types/templates/tasks/architecting.md" && grep -qF "never the running task" "$types/templates/tasks/architecting.md" && grep -qF "name no depends_on are refused" "$types/templates/tasks/architecting.md"'

chart="$types/prompts/architecting-chart/PROMPT.md"
report="$types/prompts/architecting-report/PROMPT.md"
tpl="$types/templates/tasks/architecting.md"
check "chart caps research at 4 subagents at once" 'grep -qF "at most 4 subagents at once" "$chart"'
check "the template states the mode table once, and who resolves research" \
  'grep -qF "The mode table, the one statement of which mode owns research ticket resolution" "$tpl" && grep -qF "| chart | the map, and the tickets it opens" "$tpl" && grep -qF "the research tickets it opens on its frontier" "$tpl" && grep -qF "| resolve | the one ticket the task document names" "$tpl" && grep -qF "| spec | nothing: it cites the map" "$tpl"'
check "the template's chart non-goal follows from the mode table" \
  'grep -qF "resolving any ticket but a research ticket it opened on its frontier" "$tpl" && ! grep -qF "resolving a ticket of the map, which is a resolve-mode task" "$tpl"'
check "chart owns the research tickets it opens and its Never line allows them" \
  "grep -qF \"Research is chart's own work\" \"\$chart\" && grep -qF \"its answer is a comment on it\" \"\$chart\" && grep -qF \"Never resolve, close or comment on a ticket of the map but the research tickets this chart\" \"\$chart\" && ! grep -qF \"Never resolve a ticket of the map yourself\" \"\$chart\""
check "chart drafts into pending/ and queues none" 'grep -q "pending/" "$chart" && grep -qF "Queue nothing" "$chart" && grep -qF "Never queue a task" "$chart"'
check "chart copies base: from the task file onto every draft" 'grep -qF "copied from the \`base:\` in this running task" "$chart"'
check "chart drafts one Architecting resolve-mode task per new frontier ticket" 'grep -qF "one Architecting task document (resolve mode)" "$chart"'
check "chart hands a repository edit off as a draft Developing task" \
  'grep -qF "draft a **Developing** task document" "$chart" && grep -qF "pipeline: developing" "$chart" && grep -qF "close_on_merge: true" "$chart" && grep -qF "group_description" "$chart"'
resolve="$types/prompts/architecting-resolve/PROMPT.md"
check "resolve cites the mode table and resolves the named ticket whatever its type" \
  'grep -qF "mode table in" "$resolve" && grep -qF "whatever its type" "$resolve"'
check "resolve hands a repository edit off as a draft Developing task and keeps its claim" \
  'grep -qF "draft a **Developing** task document" "$resolve" && grep -qF "pipeline: developing" "$resolve" && grep -qF "keep your claim, close" "$resolve" && grep -qF "write no Decisions-so-far line" "$resolve"'
check "resolve and chart still forbid edit, commit and push" \
  'grep -qF "Never edit a file in the repository, never commit and never push" "$resolve"'
check "the templates carry the Developing exception" \
  'grep -qF "a Developing task, instead," "$types/templates/tasks/architecting.md" && grep -qF "drafted by an Architecting lane" "$types/templates/tasks/developing.md"'
check "resolve passes at once when skip_steps names it" 'grep -qF "if it names \`resolve\`" "$resolve"'
check "resolve works only the ticket the task document names and blocks otherwise" \
  'grep -qF "It is the only ticket you" "$resolve" && grep -qF "Block, and say how, when" "$resolve" && grep -qF "Never touch a ticket other than the one named" "$resolve"'
check "resolve drafts into pending/ and queues none" \
  'grep -q "pending/" "$resolve" && grep -qF "Queue nothing" "$resolve" && grep -qF "Never queue a task" "$resolve"'
check "resolve copies base: from the task file onto every draft, and drafts select resolve mode" \
  'grep -qF "copied from the \`base:\` in this running task" "$resolve" && grep -qF "skip_steps: [chart, spec, artifact]" "$resolve"'
check "chart drafts select resolve mode" 'grep -qF "skip_steps: [chart, spec, artifact]" "$chart"'
check "the template names the three modes" 'grep -qF "[resolve, spec] is chart mode, [chart, spec, artifact] is resolve mode, [recall, chart, resolve] is spec mode" "$types/templates/tasks/architecting.md"'
check "the template body carries resolve-mode lines and the drafts keep them" \
  'grep -qF "[[resolve mode:" "$types/templates/tasks/architecting.md" && grep -qF "delete" "$types/templates/tasks/architecting.md" && grep -qF "Keep the template" "$resolve" && grep -qF "Keep the template" "$chart"'
check "resolve sends beyond-destination work to Out of scope without a ticket or a rewire" \
  'grep -qF "create no ticket for it" "$resolve" && grep -qF "from the new ticket" "$resolve" && ! grep -qF "rewire an edge" "$resolve"'
artifact="$types/prompts/architecting-artifact/PROMPT.md"
check "artifact passes at once when skip_steps names it" 'grep -qF "if it names \`artifact\`" "$artifact"'
check "artifact reads the map's Notes first and updates a named page in place, else creates one and writes the link into the Notes" \
  'grep -qF "Read the map'"'"'s Notes live" "$artifact" && grep -qF "publish with that \`url\`" "$artifact" && grep -qF "publish without \`url\`" "$artifact" && grep -qF "Overview page: <url>" "$artifact"'
check "artifact is in English, private and decides nothing" \
  'grep -qF "in English" "$artifact" && grep -qF "stays private" "$artifact" && grep -qF "Never decide anything the tickets do not say" "$artifact" && grep -qF "Never publish anything public" "$artifact"'
check "artifact passes at once in chart mode when no map was made" 'grep -qF "needed no map and none was made" "$artifact"'
check "artifact's Never list and the template allow the one Notes line (and heading) in the map's body" \
  'grep -qF "(and the Notes heading, when the map has none)" "$artifact" && grep -qF "but for the one Notes line that links the overview page" "$types/templates/tasks/architecting.md" && ! grep -qF "Create the Notes section" "$artifact"'
check "artifact blocks on a refused publish instead of retrying another way" 'grep -qF "do not retry another" "$artifact"'
check "the template's Non-goals and ACs carry the overview page" \
  'grep -qF "overview page beyond its private link" "$types/templates/tasks/architecting.md" && grep -qF "overview page is private and in English" "$types/templates/tasks/architecting.md"'
spec="$types/prompts/architecting-spec/PROMPT.md"
check "spec cites the mode table and resolves none" \
  'grep -qF "the mode table in" "$spec" && grep -qF "You own no ticket and resolve none" "$spec"'
check "spec passes at once when skip_steps names it" 'grep -qF "if it names \`spec\`" "$spec"'
check "spec builds only from Decisions so far and the closed tickets, not a conversation" \
  'grep -qF "Decisions so far" "$spec" && grep -qF "resolution comment" "$spec" && grep -qF "Nothing from this conversation" "$spec"'
check "spec blocks when a ticket it needs is still open" 'grep -qF "a ticket the spec needs is still open" "$spec"'
check "spec cites each closed ticket and re-decides none" 'grep -qF "Cite each closed ticket" "$spec" && grep -qF "Re-decide nothing" "$spec"'
check "spec opens no pull request, queues nothing and leaves the map unedited" \
  'grep -qF "opens no pull request" "$spec" && grep -qF "Never open a pull request" "$spec" && grep -qF "Never queue a task" "$spec" && grep -qF "Never edit, close, relabel or comment on the map" "$spec"'
check "report files through run-report.sh and writes findings through findings.sh" \
  'grep -qF "scripts/spoolway/run-report.sh file --urgent" "$report" && grep -qF "scripts/spoolway/findings.sh write" "$report"'
check "report writes at most five findings, none on the work issue" \
  'grep -qF "Five at most" "$report" && grep -qF "Never write on the idea issue (the work issue)" "$report"'
check "no prompt carries a closing keyword before an issue" \
  '! grep -rEiq "\b(close[sd]?|fix(e[sd])?|resolve[sd]?)[ :]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[0-9]+" "$types/prompts"/architecting-*'
check "no prompt carries app-only text" '! grep -rEiq "pnpm|expo|\bdevelop\b|\beas\b|\bsst\b|\badb\b|\bsdk\b" "$types/prompts"/architecting-* "$types/templates/tasks/architecting.md"'

# --- A throwaway consumer -------------------------------------------------------------------

plugin="$work/cache/spoolway-companion/6d82bbc6b8dc-afc78acc"
config="$work/claude"
home="$work/home"
c="$work/consumer"
mkdir -p "$plugin" "$config/plugins" "$home" "$c/.claude" "$c/.spoolway"
cp -R "$real" "$plugin/spoolway"
jq -n --arg p "$plugin" --arg sha "$REV" '{version: 2, plugins: {"spoolway-companion@spoolway-companion": [
  {scope: "user", installPath: $p, version: "6d82bbc6b8dc-afc78acc", gitCommitSha: $sha}]}}' \
  > "$config/plugins/installed_plugins.json"
jq -n '{enabledPlugins: {"spoolway-companion@spoolway-companion": true}, extraKnownMarketplaces: {"spoolway-companion": {source: {source: "github", repo: "theTestTube/spoolway-companion"}}}}' \
  > "$c/.claude/settings.json"
# The consumer's own files: this repository's config without its tracker hook, and its own scripts.
awk '/^\[issue_tracking\]/ { skip = 1; next } /^\[/ { skip = 0 } !skip' "$repo/.spoolway/config.toml" > "$c/.spoolway/config.toml"
mkdir -p "$c/scripts"
cp -R "$repo/scripts/spoolway" "$c/scripts/spoolway"
git -C "$c" init -q -b main
git -C "$c" add -A && git -C "$c" -c user.email=t@t -c user.name=t commit -qm init

out=$(CLAUDE_CONFIG_DIR="$config" bash "$plugin/spoolway/types.sh" write "$c" 2>&1); status=$?
check "the types are written into the consumer" '[ $status -eq 0 ]' "$out"
check "the consumer holds the pipeline, its six prompts and its template" \
  '[ -f "$c/.spoolway/pipelines/architecting.yml" ] && [ -s "$c/.spoolway/prompts/architecting-recall/PROMPT.md" ] && [ -s "$c/.spoolway/prompts/architecting-chart/PROMPT.md" ] && [ -s "$c/.spoolway/prompts/architecting-resolve/PROMPT.md" ] && [ -s "$c/.spoolway/prompts/architecting-spec/PROMPT.md" ] && [ -s "$c/.spoolway/prompts/architecting-report/PROMPT.md" ] && [ -s "$c/.spoolway/prompts/architecting-artifact/PROMPT.md" ] && [ -s "$c/.spoolway/templates/tasks/architecting.md" ]'

if command -v spoolway > /dev/null; then
  git -C "$c" add -A && git -C "$c" -c user.email=t@t -c user.name=t commit -qm types
  # A throwaway HOME: spoolway binds a project under it, and must never bind this worktree.
  check=$(cd "$c" && HOME="$home" timeout 120 spoolway pipeline check < /dev/null 2>&1); status=$?
  check "spoolway pipeline check passes in the consumer" '[ $status -eq 0 ]' "$(printf '%s' "$check" | tail -8)"
  check "...and lists architecting among its pipelines" 'grep -qw architecting <<<"$check"' "$(printf '%s' "$check" | tail -8)"
else
  fail "spoolway is on PATH"
fi

echo
if [ "$failures" -eq 0 ]; then echo "all passed"; else echo "$failures failure(s)"; exit 1; fi
