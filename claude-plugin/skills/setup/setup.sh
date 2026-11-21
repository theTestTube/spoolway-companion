#!/usr/bin/env bash
# The deterministic half of /spoolway-companion:setup: what the interview's answers turn into on
# disk. The skill asks, this script finds and writes.
#
#   setup.sh detect [<consumer>]             what the consumer already has, one fact per line
#   setup.sh plan <answers> [<consumer>]     what apply would do; writes nothing
#   setup.sh apply <answers> [<consumer>]    add what is missing, on a branch, uncommitted
#   setup.sh labels <owner/repo> [--create]  the spoolway:* labels the repository lacks
#   setup.sh bump <sha> [<consumer>]         move the companion's pin and retake what it ships
#   setup.sh memex plan|apply <answers>      the machine, not the checkout: memex's config and index timer
#   setup.sh spoolway-version [<version>]    the spoolway update road: As-Is, copies, To-Be, direction
#   setup.sh gap <to>                        releases in between, their notes and migrations, under ./.scratch/
#   setup.sh probe <version>                 download and hash-check the To-Be binary; installs nothing
#   setup.sh probe-run [<dir>]               sync --dry-run, pipeline check, doctor --no-live under both
#   setup.sh queue-snapshot                  every project home's tasks, lanes, branches, unpushed commits
#   setup.sh discover                        the checkouts a version change touches and what each runs on spoolway
#   setup.sh salvage <task>                  a task's diff, untracked files, logs and a verified bundle
#   setup.sh fresh-id <id>...                whether task/<id> is absent from origin
#
# <consumer> defaults to the current git checkout. <answers> is a file of `key=value` lines read
# with grep, never sourced (see SKILL.md for the keys). A line whose key is upper case is a
# .spoolway/companion.env key.
#
# What it never does: overwrite a file the consumer has, change an existing value in
# .claude/settings.json, .spoolway/config.toml or .spoolway/companion.env (a differing value is
# reported and kept), write a path .spoolway/plugin.lock lists but through types.sh write, touch
# another plugin's entry or lock, commit, push or edit a label. The one value it changes is the
# `sha` of the companion's own entry, in `bump`.
#
# The exception is `memex`: it writes outside the checkout (memex's config and the user's systemd
# units), under the same rule (add what is missing, report a differing value and keep it), and
# never from `plan` or `apply`.

set -euo pipefail

PLUGIN=spoolway-companion
MARKETPLACE=spoolway-companion
COMPANION_URL=https://github.com/theTestTube/spoolway-companion.git
LOCK=.spoolway/plugin.lock
SUBSET=.spoolway/types.subset
ENV_FILE=.spoolway/companion.env
CONFIG=.spoolway/config.toml
SETTINGS=.claude/settings.json
PROJECTS=docs/agents/projects.md
LABELS="spoolway:in-progress|1D76DB|spoolway: a task bound to this issue is queued or running
spoolway:review|5319E7|spoolway: the bound task handed over a pull request
spoolway:task|0E8A16|spoolway: closed by the workflow when its pull request merges"
ENV_KEYS="RUN_REPORT_REPO FINDINGS_REPO MATERIALIZING_REPO PAGES_DIR PAGES_LOG PAGES_COMPILE_PATTERN PAGES_GATE PAGES_COMMIT_PREFIX PIN_DRIFT_PROTECTED"

here=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin_root=$(cd -P "$here/../.." && pwd)
templates=$plugin_root/templates
types=$plugin_root/spoolway/types
config_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
installed=$config_dir/plugins/installed_plugins.json

die() { echo "spoolway-setup: $*" >&2; exit 1; }
usage() {
  echo "usage: setup.sh detect [<consumer>] | plan|apply <answers> [<consumer>] | labels <owner/repo> [--create] | bump <sha> [<consumer>] | memex plan|apply <answers> | spoolway-version [<version>] | gap <to> | probe <version> | probe-run [<dir>] | queue-snapshot | discover | salvage <task> | fresh-id <id>..." >&2
  exit 64
}
say() { printf '%s\n' "$*"; }

consumer_dir() {
  local c=${1:-}
  if [ -z "$c" ]; then c=$(git rev-parse --show-toplevel 2> /dev/null) || die "not inside a git checkout; name the consumer"; fi
  c=$(cd -P "$c" && pwd)
  git -C "$c" rev-parse --git-dir > /dev/null 2>&1 || die "$c is not a git checkout"
  printf '%s\n' "$c"
}

# --- reading ----------------------------------------------------------------------------------

# answer <key>: the last value the answers file gives the key; all_answers <key>: every value.
answer() { { grep -E "^$1=" "$answers" || true; } | tail -n 1 | cut -d= -f2-; }
all_answers() { { grep -E "^$1=" "$answers" || true; } | cut -d= -f2-; }

# env_value <file> <key>: as lib.sh's companion_env reads it, without the environment.
env_value() {
  local v
  v=$({ grep -E "^$2=" "$1" 2> /dev/null || true; } | tail -n 1 | cut -d= -f2-)
  v=${v%$'\r'}
  v="${v%"${v##*[![:space:]]}"}"
  case $v in \"*\" | \'*\') v=${v:1:${#v}-2} ;; esac
  printf '%s\n' "$v"
}
env_has() { grep -qE "^$2=" "$1" 2> /dev/null; }

# toml_value <key> under [issue_tracking]: the quoted or bare value, or nothing.
toml_value() {
  [ -f "$consumer/$CONFIG" ] || return 0
  awk -v key="$1" '
    /^\[/ { in_s = ($0 ~ /^\[issue_tracking\][[:space:]]*$/); next }
    in_s && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); sub(/[[:space:]]*(#.*)?$/, "", v)
      gsub(/^"|"$/, "", v); print v; exit
    }' "$consumer/$CONFIG"
}
toml_has() {
  [ -f "$consumer/$CONFIG" ] && awk -v key="$1" '
    /^\[/ { in_s = ($0 ~ /^\[issue_tracking\][[:space:]]*$/); next }
    in_s && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { found = 1 } END { exit !found }' "$consumer/$CONFIG"
}

# plugin_pin <name>: the sha the consumer's settings pin a plugin of that name at, under any
# marketplace; plugin_market <name>: that marketplace.
plugin_pin() {
  [ -f "$consumer/$SETTINGS" ] || return 0
  jq -r --arg n "$1" '[(.extraKnownMarketplaces // {})[] | (.source.plugins // [])[] | select(.name == $n) | .source.sha // empty] | first // empty' "$consumer/$SETTINGS"
}
plugin_market() {
  [ -f "$consumer/$SETTINGS" ] || return 0
  jq -r --arg n "$1" '[(.extraKnownMarketplaces // {}) | to_entries[] | select(any(.value.source.plugins[]?; .name == $n)) | .key] | first // empty' "$consumer/$SETTINGS"
}

# record <plugin>@<marketplace> <field>: that field of the install record for this project path.
record() {
  [ -f "$installed" ] || return 0
  jq -r --arg id "$1" --arg p "$consumer" --arg f "$2" '[(.plugins[$id] // [])[] | select(.projectPath == $p) | .[$f] // empty] | first // empty' "$installed"
}

# own_revision: the commit of the install this copy is, as types.sh reads it.
own_revision() {
  [ -f "$installed" ] || return 0
  jq -r --arg root "$plugin_root" '[.plugins[]?[]? | select(.installPath == $root) | .gitCommitSha // empty] | first // empty' "$installed"
}

# old_plugin: the name of another plugin that owns this consumer's types, or nothing. Read from
# the lock's `plugin` line, and from a `/<name>:spoolway-types` a gate or workflow names.
old_plugin() {
  local p=
  if [ -f "$consumer/$LOCK" ]; then
    p=$(sed -n 's/^plugin //p' "$consumer/$LOCK" | head -n 1)
    [ "$p" = "$PLUGIN" ] && p=
  fi
  if [ -z "$p" ]; then
    p=$(cd "$consumer" && git grep -h -o -E '/[A-Za-z0-9_.-]+:spoolway-types' -- scripts .github 2> /dev/null \
      | sed -E 's#^/([^:]+):.*#\1#' | grep -vx "$PLUGIN" | head -n 1 || true)
  fi
  printf '%s\n' "$p"
}

# locked <path>: the lock lists the path, so it is the companion's to write.
locked() { [ -f "$consumer/$LOCK" ] && cut -f2 "$consumer/$LOCK" | grep -qxF -- "$1"; }

# template_target <path under templates/>: the consumer path it is copied to.
template_target() {
  case "$1" in setup/*) echo ".spoolway/${1#setup/}" ;; github/*) echo ".github/${1#github/}" ;; *) echo "$1" ;; esac
}
template_source() {
  case "$1" in .spoolway/*) echo "$templates/setup/${1#.spoolway/}" ;; .github/*) echo "$templates/github/${1#.github/}" ;; *) echo "$templates/$1" ;; esac
}

# pipelines_taken: the pipelines this consumer takes, by name: the answer, else the subset or the
# lock on disk, else every pipeline this revision ships.
pipelines_taken() {
  local list=
  [ -n "${answers:-}" ] && list=$(answer pipelines)
  if [ -n "$list" ] && [ "$list" != all ]; then tr ' ,' '\n\n' <<<"$list" | grep .; return; fi
  if [ -z "$list" ]; then
    for f in "$consumer/$SUBSET" "$consumer/$LOCK"; do
      [ -f "$f" ] || continue
      list=$(grep -oE '\.spoolway/pipelines/[^/[:space:]]+\.yml' "$f" | sed -E 's#.*/([^/]+)\.yml$#\1#' | LC_ALL=C sort -u)
      [ -n "$list" ] && { printf '%s\n' "$list"; return; }
    done
  fi
  find "$types/setup/pipelines" -name '*.yml' -printf '%f\n' | sed 's/\.yml$//' | LC_ALL=C sort
}

# consumer_scripts: the scripts/spoolway/*.sh the taken pipelines run that the companion does not
# ship, so the consumer writes them.
consumer_scripts() {
  local p
  for p in $(pipelines_taken); do
    [ -f "$types/setup/pipelines/$p.yml" ] && grep -oE 'scripts/spoolway/[a-z0-9-]+\.sh' "$types/setup/pipelines/$p.yml"
  done | LC_ALL=C sort -u | while read -r s; do cut -f2 "$plugin_root/spoolway/types.manifest" | grep -qxF "$s" || echo "$s"; done
}

# subset_for: the consumer paths the taken pipelines need: their pipeline files, the prompts they
# name, the task template of the same name, and every path no pipeline owns.
subset_for() {
  local chosen all prompts_all prompts_chosen
  chosen=$(pipelines_taken)
  all=$(find "$types/setup/pipelines" -name '*.yml' -printf '%f\n' | sed 's/\.yml$//')
  prompts_all=$(cat "$types"/setup/pipelines/*.yml | sed -n 's/^[[:space:]]*prompt:[[:space:]]*//p' | LC_ALL=C sort -u)
  prompts_chosen=$(for p in $chosen; do sed -n 's/^[[:space:]]*prompt:[[:space:]]*//p' "$types/setup/pipelines/$p.yml"; done | LC_ALL=C sort -u)
  cut -f2 "$plugin_root/spoolway/types.manifest" | while read -r path; do
    case "$path" in
      .spoolway/pipelines/*.yml)
        n=${path##*/}; grep -qxF "${n%.yml}" <<<"$chosen" && echo "$path" ;;
      .spoolway/prompts/*/*)
        d=${path#.spoolway/prompts/}; d=${d%%/*}
        if grep -qxF "$d" <<<"$prompts_all"; then grep -qxF "$d" <<<"$prompts_chosen" && echo "$path"; else echo "$path"; fi ;;
      .spoolway/templates/tasks/*.md)
        n=${path##*/}; n=${n%.md}
        if grep -qxF "$n" <<<"$all"; then grep -qxF "$n" <<<"$chosen" && echo "$path"; else echo "$path"; fi ;;
      *) echo "$path" ;;
    esac
  done
}

tracker_doc() {
  local f=$consumer/docs/agents/issue-tracker.md
  if [ ! -f "$f" ]; then echo missing
  elif grep -qiE '^#+[[:space:]]+Wayfinding operations' "$f"; then echo present
  else echo "present, no Wayfinding operations section"; fi
}

# --- detect -----------------------------------------------------------------------------------

detect() {
  local p f
  say "consumer	$consumer"
  say "branch	$(git -C "$consumer" rev-parse --abbrev-ref HEAD 2> /dev/null || echo none)"
  p=$(old_plugin); say "old plugin	${p:-none}"
  say "companion pin	$(plugin_pin "$PLUGIN" | grep . || echo none)"
  say "companion install	$(record "$PLUGIN@$MARKETPLACE" gitCommitSha | grep . || echo none)"
  if [ -f "$consumer/$LOCK" ]; then say "lock	$(sed -n 's/^plugin //p' "$consumer/$LOCK" | head -n 1) $(sed -n 's/^revision //p' "$consumer/$LOCK" | head -n 1)"; else say "lock	none"; fi
  p=$(plugin_market wiki); say "wiki plugin	${p:+wiki@$p $(plugin_pin wiki)}${p:-none}"
  if [ -f "$consumer/$PROJECTS" ]; then say "projects	present"; else say "projects	missing"; fi
  if [ -f "$consumer/$SUBSET" ]; then say "types subset	present"; else say "types subset	missing"; fi
  if [ -f "$consumer/$CONFIG" ]; then say "config	present"; else say "config	missing"; fi
  for k in hook project_key; do
    if toml_has "$k"; then say "issue_tracking.$k	$(toml_value "$k")"; else say "issue_tracking.$k	missing"; fi
  done
  for k in $ENV_KEYS; do
    if env_has "$consumer/$ENV_FILE" "$k"; then say "env $k	$(env_value "$consumer/$ENV_FILE" "$k")"; else say "env $k	missing"; fi
  done
  for f in $(all_targets); do
    if [ -e "$consumer/$f" ]; then say "file $f	present"; else say "file $f	missing"; fi
  done
  say "issue-tracker.md	$(tracker_doc)"
  if [ -f "$consumer/docs/agents/triage-labels.md" ]; then say "triage-labels.md	present"; else say "triage-labels.md	missing"; fi
  memex_facts
}

# all_targets: every consumer path setup may write from a template, plus the scripts with none.
all_targets() {
  { (cd "$templates" && find . -type f -printf '%P\n') | while read -r t; do template_target "$t"; done
    consumer_scripts; } | LC_ALL=C sort -u
}

# --- writing ----------------------------------------------------------------------------------

dry=0
changed=0
note() { say "$*"; }
act() { changed=1; if [ $dry = 1 ]; then say "would: $*"; else say "$*"; fi; }

ensure_branch() {
  local want=$1 cur
  cur=$(git -C "$consumer" rev-parse --abbrev-ref HEAD 2> /dev/null || echo HEAD)
  [ "$cur" = "$want" ] && return 0
  if [ $dry = 1 ]; then say "would switch to branch $want"; return 0; fi
  if git -C "$consumer" show-ref --verify --quiet "refs/heads/$want"; then
    git -C "$consumer" switch -q "$want"
  else
    git -C "$consumer" switch -q -c "$want"
  fi
  say "on branch $want"
}

# put_file <consumer path> <source file>: copy when missing, keep and report when present.
put_file() {
  local dst=$1 src=$2
  if locked "$dst"; then note "kept $dst: plugin.lock lists it"; return; fi
  if [ -e "$consumer/$dst" ]; then note "kept $dst: present"; return; fi
  act "wrote $dst"
  [ $dry = 1 ] && return
  mkdir -p "$(dirname "$consumer/$dst")"
  cp "$src" "$consumer/$dst"
  [ -x "$src" ] && chmod 755 "$consumer/$dst"
  return 0
}

put_text() {
  local dst=$1 tmp
  tmp=$(mktemp); cat > "$tmp"
  put_file "$dst" "$tmp"
  rm -f "$tmp"
}

env_quote() { case $1 in *[[:space:]\"\'\#\$\\\`\|\;\&\<\>\(\)\*\?\[]*) printf '"%s"' "$1" ;; *) printf '%s' "$1" ;; esac; }

put_env() {
  local key=$1 value=$2 f=$consumer/$ENV_FILE old
  if env_has "$f" "$key"; then
    old=$(env_value "$f" "$key")
    [ "$old" = "$value" ] && note "kept $ENV_FILE $key: present" || note "kept $ENV_FILE $key: it is \"$old\", the answer was \"$value\"; change it by hand if you mean it"
    return
  fi
  act "added $key to $ENV_FILE"
  [ $dry = 1 ] && return
  mkdir -p "$consumer/.spoolway"
  if [ ! -f "$f" ]; then
    printf '%s\n' "# Settings the spoolway-companion scripts read, one KEY=value per line, read with grep and never" \
      "# sourced. An environment variable of the same name wins. Tracked: no private destination here." > "$f"
  fi
  printf '%s=%s\n' "$key" "$(env_quote "$value")" >> "$f"
}

put_toml() {
  local key=$1 value=$2 f=$consumer/$CONFIG old
  if [ ! -f "$f" ]; then note "skipped issue_tracking.$key: no $CONFIG; run \`spoolway init\` here, then setup again"; return; fi
  if toml_has "$key"; then
    old=$(toml_value "$key")
    [ "$old" = "$value" ] && note "kept $CONFIG issue_tracking.$key: present" || note "kept $CONFIG issue_tracking.$key: it is \"$old\", the answer was \"$value\"; change it by hand if you mean it"
    return
  fi
  act "added issue_tracking.$key to $CONFIG"
  [ $dry = 1 ] && return
  if grep -qE '^\[issue_tracking\][[:space:]]*$' "$f"; then
    awk -v line="$key = \"$value\"" '{ print } /^\[issue_tracking\][[:space:]]*$/ { print line }' "$f" > "$f.new" && mv "$f.new" "$f"
  else
    printf '\n[issue_tracking]\n%s = "%s"\n' "$key" "$value" >> "$f"
  fi
}

# put_plugin_entry <marketplace> <plugin> <url> <sha> [<ref>]: add the inline marketplace entry and
# its enabledPlugins key when the plugin is pinned nowhere; never change an existing entry.
put_plugin_entry() {
  local market=$1 name=$2 url=$3 sha=$4 ref=${5:-} f=$consumer/$SETTINGS have
  have=$(plugin_market "$name")
  if [ -n "$have" ]; then
    note "kept $SETTINGS entry $name@$have: present"
  else
    act "added $name@$market to $SETTINGS"
    if [ $dry = 0 ]; then
      mkdir -p "$consumer/.claude"
      [ -f "$f" ] || echo '{}' > "$f"
      jq --arg m "$market" --arg n "$name" --arg u "$url" --arg s "$sha" --arg r "$ref" '
        .extraKnownMarketplaces //= {}
        | .extraKnownMarketplaces[$m] //= {source: {source: "settings", name: $m, plugins: []}}
        | .extraKnownMarketplaces[$m].source.plugins += [{name: $n, source: ({source: "git-subdir", url: $u, path: "claude-plugin"}
            + (if $r == "" then {} else {ref: $r} end) + {sha: $s})}]' "$f" > "$f.new" && mv "$f.new" "$f"
    fi
    have=$market
  fi
  if [ -f "$f" ] && jq -e --arg k "$name@$have" '(.enabledPlugins // {}) | has($k)' "$f" > /dev/null; then
    return
  fi
  act "enabled $name@$have in $SETTINGS"
  [ $dry = 1 ] && return
  jq --arg k "$name@$have" '.enabledPlugins //= {} | .enabledPlugins[$k] = true' "$f" > "$f.new" && mv "$f.new" "$f"
}

# install_plugin <plugin> <marketplace>: install it for this project path, or update the record
# when its revision is not the pin. Reports a record the update left behind (plugin#32's lag).
install_plugin() {
  local id=$1@$2 pin rec verb
  pin=$(plugin_pin "$1")
  rec=$(record "$id" gitCommitSha)
  if [ -n "$rec" ] && [ "$rec" = "$pin" ]; then note "kept the $id install: at ${pin:0:12}"; return 0; fi
  verb=install; [ -n "$rec" ] && verb=update
  if [ $dry = 1 ]; then act "$verb $id for this project path"; return 0; fi
  if ! command -v claude > /dev/null; then
    note "to do: no \`claude\` on PATH; run \`claude plugin $verb $id --scope project\` in $consumer, restart Claude Code"
    return 1
  fi
  act "ran claude plugin $verb $id --scope project"
  (cd "$consumer" && CLAUDE_CODE_SYNC_PLUGIN_INSTALL=1 claude plugin "$verb" "$id" --scope project < /dev/null) || {
    note "to do: \`claude plugin $verb $id --scope project\` failed above; it needs a signed-in, trusted folder"
    return 1
  }
  rec=$(record "$id" gitCommitSha)
  if [ "$rec" != "$pin" ]; then
    note "to do: the $id record for this path is at ${rec:-nothing} after $verb, the pin is ${pin:0:12}. The marketplace already at the pin leaves a stale per-path record alone: repoint its installPath and gitCommitSha in $installed, then setup again"
    return 1
  fi
}

take_types() {
  local old root lock_rev pin
  old=$(old_plugin)
  if [ -n "$old" ]; then note "kept the types: they belong to the $old plugin; its cut-over is its own work, so plugin.lock and its gate are untouched"; return; fi
  pin=$(plugin_pin "$PLUGIN")
  lock_rev=$( [ -f "$consumer/$LOCK" ] && sed -n 's/^revision //p' "$consumer/$LOCK" | head -n 1 || true)
  if [ -n "$pin" ] && [ "$lock_rev" = "$pin" ]; then note "kept the types: $LOCK is at ${pin:0:12}"; return; fi
  if [ $dry = 1 ]; then act "write the types at ${pin:0:12} through types.sh write"; return; fi
  root=$(record "$PLUGIN@$MARKETPLACE" installPath)
  [ -n "$root" ] && [ -x "$root/spoolway/types.sh" ] || { note "to do: no installed $PLUGIN for this path; install it, restart, and run /$PLUGIN:spoolway-types"; return; }
  act "took the types:"
  bash "$root/spoolway/types.sh" write "$consumer"
}

projects_doc() {
  local topology=$1 extra root rule mat
  extra=$(answer extra_repos); root=$(answer worktree_root); rule=$(answer repos_rule)
  mat=$(answer MATERIALIZING_REPO)
  printf '# Projects\n\nThe repositories spoolway works in. Pipeline prompts read this file; keep it current.\n\n'
  printf '| Repository | Role |\n|---|---|\n| %s | this repository |\n' "$(answer project_key | grep . || echo "${consumer##*/}")"
  for r in $extra; do printf '| %s | extra repository |\n' "$r"; done
  printf '\n## The `repos` rule\n\n'
  if [ "$topology" = multi ]; then
    printf '%s\n' "${rule:-A task names in \`repos\` every repository its change touches, this one first.}"
    printf '\nExtra repositories have their checkouts beside this one, `../<name>`, and their worktrees at `%s/<name>/<branch>`, a `/` in the branch written `-` (`EXTRA_REPOS` and `EXTRA_WORKTREE_ROOT` in `.spoolway/companion.env`).\n' "${root:-<worktree root>}"
  else
    printf 'This is a mono-repo: a task names no `repos`, or only this repository.\n'
  fi
  if [ -n "$mat" ]; then printf '\n## Materializing\n\nSpecs and their tickets live in `%s`.\n' "$mat"; fi
  printf '\n## Private repositories\n\nA private destination stays in a machine-local file `COMPANION_ENV_FILE` names, never here.\n'
}

checks_script() {
  local body
  body=$(all_answers checks | grep . || true)
  [ -n "$body" ] || body='echo "checks: no gate written yet; put your CI'"'"'s commands between the gates markers" >&2
exit 1'
  awk -v body="$body" '$0 == "@CHECKS@" { print body; next } { print }' "$templates/scripts/spoolway/checks.sh"
}

apply() {
  local topology tracking key value s t old wiki sha
  [ -f "$answers" ] || die "no answers file $answers"
  topology=$(answer topology); topology=${topology:-mono}
  # The pin: what the consumer has, else the answer, else the revision of this very copy.
  sha=$(plugin_pin "$PLUGIN")
  [ -n "$sha" ] || sha=$(answer companion_sha)
  [ -n "$sha" ] || sha=$(own_revision)
  [[ $sha =~ ^[0-9a-f]{40}$ ]] || die "no companion revision to pin: answer companion_sha with a full commit sha, or run this from the installed plugin. Nothing was written"
  if [ "$(answer wiki)" = yes ] && [ -z "$(plugin_market wiki)" ] && [ -n "$(answer wiki_sha)" ] && ! [[ $(answer wiki_sha) =~ ^[0-9a-f]{40}$ ]]; then
    die "wiki_sha \"$(answer wiki_sha)\" is no full commit sha. Nothing was written"
  fi
  old=$(old_plugin)
  ensure_branch "$(answer branch | grep . || echo spoolway-companion-setup)"
  [ -n "$old" ] && note "found the $old plugin: the companion goes in beside it and nothing of $old is touched"

  # (1) topology
  if [ -e "$consumer/$PROJECTS" ]; then note "kept $PROJECTS: present"; else projects_doc "$topology" | put_text "$PROJECTS"; fi
  # The extra-* scripts read the extra repositories and their worktree root from companion.env.
  if [ "$topology" = multi ]; then
    if [ -n "$(answer extra_repos)" ]; then put_env EXTRA_REPOS "$(answer extra_repos)"
    else note "to do: topology is multi and extra_repos is empty; set EXTRA_REPOS in $ENV_FILE"; fi
    if [ -n "$(answer worktree_root)" ]; then put_env EXTRA_WORKTREE_ROOT "$(answer worktree_root)"
    else note "to do: topology is multi and worktree_root is empty; set EXTRA_WORKTREE_ROOT in $ENV_FILE"; fi
  fi
  # (2) pipelines
  if [ -n "$(answer pipelines)" ] && [ "$(answer pipelines)" != all ] && [ -z "$old" ]; then
    if [ -e "$consumer/$SUBSET" ]; then note "kept $SUBSET: present"
    else { echo "# The companion paths this consumer takes; see types.sh."; subset_for; } | put_text "$SUBSET"; fi
  fi
  # (3) issue tracking
  tracking=$(answer issue_tracking)
  if [ "$tracking" = yes ]; then
    put_file .spoolway/hooks/github.sh "$templates/setup/hooks/github.sh"
    put_file .github/workflows/spoolway-issues.yml "$templates/github/workflows/spoolway-issues.yml"
    put_toml hook github.sh
    [ -n "$(answer project_key)" ] && put_toml project_key "$(answer project_key)"
  fi
  # (4) and (5): destinations and wiki keys
  while IFS= read -r line; do
    key=${line%%=*}; value=${line#*=}
    put_env "$key" "$value"
  done < <(grep -E '^[A-Z][A-Z0-9_]*=' "$answers" || true)
  # (6) consumer scripts
  for s in $(consumer_scripts); do
    case "$s" in
      scripts/spoolway/checks.sh) checks_script | put_text "$s"; [ -e "$consumer/$s" ] && [ $dry = 0 ] && chmod 755 "$consumer/$s" ;;
      *)
        if [ -f "$templates/$s" ]; then put_file "$s" "$templates/$s"
        elif [ -e "$consumer/$s" ]; then note "kept $s: present"
        else note "to do: write $s by hand: the companion has no template for it yet"; fi ;;
    esac
  done

  # the companion itself, and optional tools
  put_plugin_entry "$MARKETPLACE" "$PLUGIN" "$(answer companion_url | grep . || echo "$COMPANION_URL")" "$sha"
  wiki=$(answer wiki)
  if [ "$wiki" = yes ]; then
    if [ -z "$(plugin_market wiki)" ] && { [ -z "$(answer wiki_url)" ] || [ -z "$(answer wiki_sha)" ]; }; then
      note "to do: llm-wiki needs wiki_url and wiki_sha to be pinned"
    else
      put_plugin_entry "$(answer wiki_marketplace | grep . || echo llm-wiki)" wiki "$(answer wiki_url)" "$(answer wiki_sha)" "$(answer wiki_ref)"
    fi
  fi
  if install_plugin "$PLUGIN" "$MARKETPLACE"; then take_types; else note "to do: the types are not taken until the install is at the pin"; fi
  [ -n "$(plugin_market wiki)" ] && [ "$wiki" = yes ] && { install_plugin wiki "$(plugin_market wiki)" || true; }

  t=$(tracker_doc)
  [ "$t" = present ] || note "to do: docs/agents/issue-tracker.md is $t; run /setup-matt-pocock-skills with the person's yes"
  [ -f "$consumer/docs/agents/triage-labels.md" ] || note "to do: docs/agents/triage-labels.md is missing; run /setup-matt-pocock-skills with the person's yes"
  if [ $changed = 0 ]; then say "nothing to add"
  elif [ $dry = 0 ]; then say "left uncommitted on $(git -C "$consumer" rev-parse --abbrev-ref HEAD); review, commit and open the pull request yourself; restart Claude Code"; fi
}

# --- memex ------------------------------------------------------------------------------------
# The one part of setup that is the machine's, not the checkout's: the memory index's config in
# ~/.memex and the user's systemd units. It follows the same rule as the rest: add what is
# missing, report a differing value and keep it. Nothing here shows in `git status`.

memex_cfg() { printf '%s\n' "$HOME/.memex/config.toml"; }
memex_units() { printf '%s\n' "$HOME/.config/systemd/user"; }

# mcfg_value <key>, mcfg_has <key>: a top-level key of memex's config.toml (above its first table).
mcfg_value() {
  [ -f "$(memex_cfg)" ] || return 0
  awk -v key="$1" '
    /^\[/ { exit }
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); sub(/[[:space:]]*(#.*)?$/, "", v); gsub(/^"|"$/, "", v); print v; exit
    }' "$(memex_cfg)"
}
mcfg_has() {
  [ -f "$(memex_cfg)" ] && awk -v key="$1" '
    /^\[/ { exit }
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { found = 1 } END { exit !found }' "$(memex_cfg)"
}

# put_mcfg <key> <toml literal> <why>: add the key above the first table when it is missing.
put_mcfg() {
  local key=$1 want=$2 why=$3 f old
  f=$(memex_cfg)
  if mcfg_has "$key"; then
    old=$(mcfg_value "$key")
    if [ "$old" = "${want//\"/}" ]; then note "kept $f $key: present"
    else note "kept $f $key: it is \"$old\", the answer was \"${want//\"/}\"; change it by hand if you mean it"; fi
    return
  fi
  act "added $key = $want to $f"
  [ $dry = 1 ] && return
  mkdir -p "$(dirname "$f")"
  {
    printf '# %s\n%s = %s\n' "$why" "$key" "$want"
    if [ -f "$f" ]; then printf '\n'; cat "$f"; fi
  } > "$f.new" && mv "$f.new" "$f"
}

# put_machine_file <path> (content on stdin): write it when missing; keep it, and say so when it
# differs, when present.
put_machine_file() {
  local dst=$1 tmp
  tmp=$(mktemp); cat > "$tmp"
  if [ ! -e "$dst" ]; then
    act "wrote $dst"
    if [ $dry = 0 ]; then mkdir -p "$(dirname "$dst")"; cp "$tmp" "$dst"; fi
  elif cmp -s "$tmp" "$dst"; then note "kept $dst: present"
  else note "kept $dst: present and different from what setup would write"; fi
  rm -f "$tmp"
}

# memex_schedule_now: none, boot, hourly or other, from the units on disk.
memex_schedule_now() {
  local t
  t=$(memex_units)/memex-index.timer
  if [ ! -f "$t" ]; then echo none
  elif grep -qs '^OnStartupSec=.' "$t.d"/*.conf; then echo boot
  elif grep -q '^OnUnitActiveSec=' "$t"; then echo hourly
  else echo other; fi
}

# memex_vectors: the vector count `memex index stats` reports, or nothing.
memex_vectors() {
  [ -d "$HOME/.memex/index" ] || return 0   # `memex index stats` would create an empty index
  timeout 60 memex index stats --non-interactive --no-update-check < /dev/null 2> /dev/null | sed -n 's/^vectors: \([0-9][0-9]*\).*/\1/p' | head -n 1  || true
}

memex_mem_available() { awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo 2> /dev/null; }

# memex_fastembed_env: the model cache directory the systemd user manager hands a service.
memex_fastembed_env() {
  command -v systemctl > /dev/null || return 0
  systemctl --user show-environment 2> /dev/null | sed -n 's/^FASTEMBED_CACHE_DIR=//p' | head -n 1 || true
}

memex_facts() {
  local v
  if command -v memex > /dev/null; then say "memex	$(command -v memex) $(timeout 20 memex --version --no-update-check < /dev/null 2> /dev/null | head -n 1)"
  else say "memex	none"; return; fi
  if [ -f "$(memex_cfg)" ]; then say "memex config	present"; else say "memex config	missing"; fi
  v=$(mcfg_value embeddings); say "memex embeddings	${v:-unset}"
  v=$(mcfg_value auto_index_on_search); say "memex auto_index_on_search	${v:-unset}"
  v=$(memex_vectors); say "memex vectors	${v:-unknown}"
  say "memex schedule	$(memex_schedule_now)"
  if [ -f "$(memex_units)/memex-index.service.d/limits.conf" ]; then say "memex limits drop-in	present"; else say "memex limits drop-in	missing"; fi
  v=$(memex_fastembed_env); say "memex FASTEMBED_CACHE_DIR	${v:-unset}"
  say "memex mem available mb	$(memex_mem_available | grep . || echo unknown)"
}

# memex_install_schedule <hourly|boot>: embeddings on, the timer, its limits.
memex_install_schedule() {
  local want=$1 now vectors units
  units=$(memex_units)
  if [ "$(uname -s)" != Linux ] || ! command -v systemctl > /dev/null; then
    note "to do: setup writes systemd units only; run \`memex daemon enable --interval 3600\` by hand on this machine"; return
  fi
  now=$(memex_schedule_now)
  if ! mcfg_has embeddings; then
    put_mcfg embeddings '"local"' "The timer runs plain \`memex index\`, which embeds only when this is on."
  else
    case $(mcfg_value embeddings) in
      true | local | remote) note "kept $(memex_cfg) embeddings: $(mcfg_value embeddings)" ;;
      *) note "to do: $(memex_cfg) embeddings is \"$(mcfg_value embeddings)\": the timer would index the text only and the vectors decay; set it to \"local\" by hand" ;;
    esac
  fi
  vectors=$(memex_vectors)
  if [ -z "$vectors" ] || [ "$vectors" -lt 1000 ]; then
    note "to do: the index holds ${vectors:-no} vectors. A first embed pass over a whole history takes over an hour and about 4 GB, and the timer's memory limit would throttle it, so the timer was not installed: close heavy programs, run \`memex index embed\` once by hand, then run setup again"
    return
  fi
  # The drop-ins first, so the one restart `daemon enable` does loads them.
  put_machine_file "$units/memex-index.service.d/limits.conf" <<'EOF'
# Keep the index pass from competing with the work on this machine. MemoryHigh throttles
# instead of killing; MemoryMax is the hard backstop.
[Service]
Nice=15
CPUWeight=20
CPUQuota=400%
IOWeight=20
MemoryHigh=2500M
MemoryMax=4500M
EOF
  case "$want:$now" in
    boot:none)
      put_machine_file "$units/memex-index.timer.d/boot-only.conf" <<'EOF'
# One run per user session, when memory is freest; never hourly. The empty assignments reset
# what `memex daemon enable` generates.
[Timer]
OnBootSec=
OnUnitActiveSec=
OnStartupSec=3min
EOF
      ;;
    hourly:none | boot:boot | hourly:hourly) ;;
    *) note "kept the memex-index timer as it is ($now), the answer was $want: delete $units/memex-index.timer.d/boot-only.conf (or write it) by hand, then \`systemctl --user daemon-reload\`" ;;
  esac
  if [ "$now" = none ]; then
    act "ran memex daemon enable --interval 3600: installs the timer and starts it, so one pass runs right away"
    if [ $dry = 0 ]; then
      timeout 60 memex daemon enable --interval 3600 --non-interactive --no-update-check < /dev/null \
        || note "to do: \`memex daemon enable\` failed above; the units and config are as far as it got"
    fi
  elif [ $dry = 0 ]; then
    systemctl --user daemon-reload || true
  fi
  if [ -z "$(memex_fastembed_env)" ]; then
    note "to do: FASTEMBED_CACHE_DIR is not in the systemd user environment: the timer's first model download (1.2 GB) would land in the service's working directory. Set it in ~/.config/environment.d/fastembed.conf and log in again"
  fi
}

memex_apply() {
  local sched auto now
  sched=$(answer memex_schedule); auto=$(answer memex_auto_index_on_search)
  case $sched in '' | none | hourly | boot) ;; *) die "memex_schedule \"$sched\" is none, hourly or boot" ;; esac
  case $auto in '' | true | false) ;; *) die "memex_auto_index_on_search \"$auto\" is true or false" ;; esac
  if [ -z "$sched" ] && [ -z "$auto" ]; then say "nothing asked of memex"; return; fi
  if ! command -v memex > /dev/null; then note "to do: memex is not on PATH, so nothing was done for it; install it, then run setup again"; return; fi
  # auto_index_on_search before the timer: `memex daemon enable` adds it as false only when the key is missing.
  case $auto in
    true) put_mcfg auto_index_on_search true "A search first re-scans the history and indexes what is new; nothing else keeps the index fresh." ;;
    false) put_mcfg auto_index_on_search false "Background indexing handles freshness; avoid duplicate scan work during search." ;;
  esac
  case $sched in
    hourly | boot) memex_install_schedule "$sched" ;;
    none)
      now=$(memex_schedule_now)
      if [ "$now" = none ]; then note "no memex schedule: run \`memex index embed\` by hand when the vectors fall behind"
      else note "kept the memex-index timer ($now): setup never removes one; \`memex daemon disable\` does"; fi ;;
  esac
  if [ $changed = 0 ]; then say "nothing to add"; elif [ $dry = 0 ]; then say "wrote outside the checkout (see the lines above); none of it is in git"; fi
}

# --- labels -----------------------------------------------------------------------------------

labels() {
  local repo=$1 create=${2:-} have name color desc missing=0
  have=$(gh label list -R "$repo" --limit 500 --json name --jq '.[].name')
  while IFS='|' read -r name color desc; do
    if grep -qxF "$name" <<<"$have"; then say "kept label $name: present"; continue; fi
    missing=1
    if [ "$create" = --create ]; then
      gh label create "$name" -R "$repo" --color "$color" --description "$desc" > /dev/null
      say "created label $name"
    else
      say "would create label $name"
    fi
  done <<<"$LABELS"
  [ $missing = 1 ] || say "every spoolway label is present"
}

# --- bump -------------------------------------------------------------------------------------

bump() {
  local new=$1 old count old_root new_root t src prev
  [[ $new =~ ^[0-9a-f]{40}$ ]] || die "$new is no full commit sha"
  old=$(plugin_pin "$PLUGIN")
  [ -n "$old" ] || die "$consumer/$SETTINGS pins no $PLUGIN; run setup first"
  ensure_branch "spoolway-companion-${new:0:12}"
  old_root=$(record "$PLUGIN@$MARKETPLACE" installPath)
  if [ "$old" = "$new" ]; then
    note "kept the pin: already ${new:0:12}"
  else
    count=$(grep -o "$old" "$consumer/$SETTINGS" | wc -l)
    [ "$count" -eq 1 ] || die "$SETTINGS names ${old:0:12} $count times; move the $PLUGIN sha by hand"
    sed -i "s/$old/$new/" "$consumer/$SETTINGS"
    act "moved the $PLUGIN pin ${old:0:12} -> ${new:0:12}"
  fi
  if ! install_plugin "$PLUGIN" "$MARKETPLACE"; then note "stopped before the types: the install is not at the pin"; return 0; fi
  [ -n "$(plugin_market wiki)" ] && { install_plugin wiki "$(plugin_market wiki)" || true; }
  take_types
  new_root=$(record "$PLUGIN@$MARKETPLACE" installPath)
  # what is new and missing
  for s in $(consumer_scripts); do
    if [ -e "$consumer/$s" ]; then continue; fi
    if [ -f "$new_root/templates/$s" ]; then put_file "$s" "$new_root/templates/$s"; else note "to do: write $s by hand: the companion has no template for it yet"; fi
  done
  for k in $ENV_KEYS; do env_has "$consumer/$ENV_FILE" "$k" || note "unset $ENV_FILE key $k: add it if this consumer needs it"; done
  # what changed upstream in the templates the consumer copied
  for t in $(cd "$new_root/templates" && find . -type f -printf '%P\n' | LC_ALL=C sort); do
    dst=$(template_target "$t")
    [ -e "$consumer/$dst" ] || continue
    src=$new_root/templates/$t
    prev=
    [ -n "$old_root" ] && [ "$old_root" != "$new_root" ] && [ -f "$old_root/templates/$t" ] && prev=$old_root/templates/$t
    if [ -n "$prev" ]; then
      cmp -s "$prev" "$src" && continue
      say "template $t changed upstream; apply to $dst by hand:"
      diff -u --label "a/$t" --label "b/$t" "$prev" "$src" || true
    elif ! cmp -s "$consumer/$dst" "$src"; then
      say "template $t differs from $dst (the previous template is gone, so this is your file against the new one):"
      diff -u --label "a/$dst" --label "b/$t" "$consumer/$dst" "$src" || true
    fi
  done
  say "left uncommitted on $(git -C "$consumer" rev-parse --abbrev-ref HEAD); restart Claude Code to load ${new:0:12}"
}

# --- the spoolway update road ------------------------------------------------------------------
# Reads, probes and drafts: writes only under ./.scratch/ of the checkout it runs in, installs
# nothing, and never runs a real `sync`.

SPOOLWAY_REPO=marvingygas/spoolway
UPDATE_CMDS="sync --dry-run|pipeline check|doctor --no-live"

# sp_version <binary>: the number `--version` prints, without a leading v.
sp_version() { local v; v=$(timeout 30 "$1" --version < /dev/null 2> /dev/null | head -n 1 | awk '{print $NF}') || true; printf '%s\n' "${v#v}"; }
# vgt <a> <b>: a is a newer version than b.
vgt() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]; }
direction() { if [ "$1" = "$2" ]; then echo equal; elif vgt "$2" "$1"; then echo forward; else echo backward; fi; }
# spw <timeout> <args>…: a spoolway read, never waiting on a terminal.
spw() { local t=$1; shift; timeout "$t" spoolway "$@" < /dev/null; }

# scratch_root: the checkout's ./.scratch/, which git must ignore.
# Sets $scratch; call it directly, never in a command substitution, so its die ends the run.
scratch_root() {
  git -C "$consumer" check-ignore -q .scratch/x || die "./.scratch/ is not git-ignored in $consumer; ask the person to ignore it first"
  mkdir -p "$consumer/.scratch"
  scratch=$consumer/.scratch
}
# update_dir <as-is> <to-be>
update_dir() { scratch_root; mkdir -p "$scratch/spoolway-$1-to-$2"; }
as_is() { local v; v=$(sp_version spoolway); [ -n "$v" ] || die "spoolway --version prints nothing"; printf '%s\n' "$v"; }

# spoolway-version [<version>]: As-Is, every copy on the PATH, To-Be and the direction.
spoolway_version() {
  local want=${1:-} asis tobe kind=latest tag p v
  asis=$(as_is)
  say "as-is	$asis"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    say "copy	$p	$(sp_version "$p")"
  done < <(type -a spoolway 2> /dev/null | awk '{print $NF}' | awk '!seen[$0]++')
  if [ -n "$want" ]; then
    want=${want#v}; kind=named
    tag=$(gh release view "v$want" --repo "$SPOOLWAY_REPO" --json tagName | jq -r .tagName) || die "no release v$want in $SPOOLWAY_REPO"
  else
    tag=$(gh release view --repo "$SPOOLWAY_REPO" --json tagName | jq -r .tagName) || die "cannot read the latest release of $SPOOLWAY_REPO"
  fi
  tobe=${tag#v}
  say "to-be	$tobe	$kind	tag $tag"
  say "direction	$(direction "$asis" "$tobe")"
}

# gap <to>: the releases in between, their notes, docs/migrations.md at the tag.
gap() {
  local tobe=${1#v} asis dir dirn list tag date v lo hi n=0 body
  asis=$(as_is)
  dirn=$(direction "$asis" "$tobe")
  say "as-is	$asis"; say "to-be	$tobe"; say "direction	$dirn"
  [ "$dirn" != equal ] || { say "equal: nothing to review"; return; }
  update_dir "$asis" "$tobe"; dir=$scratch/spoolway-$asis-to-$tobe
  if [ "$dirn" = forward ]; then lo=$asis hi=$tobe; else lo=$tobe hi=$asis; fi
  list=$(gh release list --repo "$SPOOLWAY_REPO" --limit 200 --json tagName,publishedAt | jq -r '.[] | [.tagName, .publishedAt] | @tsv') || die "cannot list the releases of $SPOOLWAY_REPO"
  mkdir -p "$dir/notes" "$dir/migrations"
  while IFS=$'\t' read -r tag date; do
    [ -n "$tag" ] || continue
    v=${tag#v}
    vgt "$v" "$lo" && ! vgt "$v" "$hi" || continue
    n=$((n + 1))
    body=$(gh release view "$tag" --repo "$SPOOLWAY_REPO" --json body | jq -r .body) || die "cannot read the notes of $tag"
    printf '%s\n' "$body" > "$dir/notes/$tag.md"
    if grep -qiE '^#+ .*breaking' "$dir/notes/$tag.md"; then
      say "release	$tag	${date%%T*}	notes $dir/notes/$tag.md	breaking-changes section: present"
    else
      say "release	$tag	${date%%T*}	notes $dir/notes/$tag.md	breaking-changes section: none"
    fi
  done < <(printf '%s\n' "$list" | sort -t$'\t' -k1,1V)
  [ $n -gt 0 ] || say "no release between $lo and $hi"
  gap_migrations "$dir" "v$tobe"
  [ "$dirn" = backward ] && gap_migrations "$dir" "v$asis"
  say "saved under $dir"
  return 0
}
gap_migrations() {
  local dir=$1 tag=$2
  if gh api -H 'Accept: application/vnd.github.raw' "repos/$SPOOLWAY_REPO/contents/docs/migrations.md?ref=$tag" > "$dir/migrations/$tag.md" 2> /dev/null; then
    say "migrations	$tag	$dir/migrations/$tag.md"
  else
    rm -f "$dir/migrations/$tag.md"; say "migrations	$tag	none at that tag"
  fi
}

# probe <version>: the platform's asset and SHA256SUMS into <dir>/bin/, hash-checked, never installed.
probe() {
  local tobe=${1#v} tag asis dir os arch asset names
  tag=v$tobe; asis=$(as_is)
  update_dir "$asis" "$tobe"; dir=$scratch/spoolway-$asis-to-$tobe
  os=$(uname -s | tr 'A-Z' 'a-z')
  case $(uname -m) in x86_64 | amd64) arch=x64 ;; aarch64 | arm64) arch=arm64 ;; *) die "no asset for $(uname -m)" ;; esac
  asset=spoolway-$os-$arch
  names=$(gh release view "$tag" --repo "$SPOOLWAY_REPO" --json assets | jq -r '.assets[].name') || die "no release $tag"
  grep -qxF "$asset" <<<"$names" || die "release $tag lists no $asset; it lists: $(tr '\n' ' ' <<<"$names")"
  grep -qxF SHA256SUMS <<<"$names" || die "release $tag lists no SHA256SUMS"
  mkdir -p "$dir/bin"
  rm -f "$dir/bin/spoolway" "$dir/bin/$asset" "$dir/bin/SHA256SUMS"
  gh release download "$tag" --repo "$SPOOLWAY_REPO" --pattern "$asset" --pattern SHA256SUMS --dir "$dir/bin" --clobber > /dev/null || die "download of $tag failed"
  say "downloaded	$dir/bin/$asset	$dir/bin/SHA256SUMS"
  if ! (cd "$dir/bin" && sha256sum -c --ignore-missing SHA256SUMS > "$dir/bin/sha256sum.out" 2>&1); then
    rm -f "$dir/bin/$asset"
    say "checksum	MISMATCH	$(tr '\n' ' ' < "$dir/bin/sha256sum.out")"
    die "the hash of $asset does not match SHA256SUMS: the download was deleted, nothing was made executable or linked"
  fi
  say "checksum	ok	$asset"
  chmod +x "$dir/bin/$asset"
  ln -sf "$asset" "$dir/bin/spoolway"
  [ "$(sp_version "$dir/bin/spoolway")" = "$tobe" ] || die "$dir/bin/spoolway --version prints \"$(sp_version "$dir/bin/spoolway")\", not $tobe"
  say "probe	$dir/bin/spoolway	$tobe	installed nowhere"
}

# probe_dir [<dir>]: the given probe directory, else the newest holding a bin/spoolway.
probe_dir() {
  local d=${1:-}
  if [ -z "$d" ]; then
    scratch_root
    d=$(ls -dt "$scratch"/spoolway-*-to-* 2> /dev/null | while read -r x; do [ -x "$x/bin/spoolway" ] && { echo "$x"; break; }; done)
    [ -n "$d" ] || die "no probe under ./.scratch/: run probe <version> first"
  fi
  [ -x "$d/bin/spoolway" ] || die "$d/bin/spoolway is missing"
  (cd -P "$d" && pwd)
}

# probe-run [<dir>]: sync --dry-run, pipeline check and doctor --no-live under both binaries.
probe_run() {
  local dir old new side bin cmd slug status unset_args=() k
  dir=$(probe_dir "${1:-}")
  old=$(sp_version spoolway); new=$(sp_version "$dir/bin/spoolway")
  say "as-is	$old	$(command -v spoolway)"; say "to-be	$new	$dir/bin/spoolway"
  # A key the checkout's companion.env names, or the companion knows, must come from the file.
  for k in $ENV_KEYS $( { grep -hoE '^[A-Z_][A-Z0-9_]*=' "$consumer/$ENV_FILE" 2> /dev/null || true; } | tr -d '=' ); do unset_args+=(-u "$k"); done
  mkdir -p "$dir/as-is" "$dir/to-be"
  for side in as-is to-be; do
    for cmd in sync-dry-run pipeline-check doctor-no-live; do
      case $cmd in
        sync-dry-run) set -- sync --dry-run ;;
        pipeline-check) set -- pipeline check ;;
        doctor-no-live) set -- doctor --no-live ;;
      esac
      status=0
      if [ $side = to-be ]; then
        (cd "$consumer" && PATH="$dir/bin:$PATH" env "${unset_args[@]}" timeout 300 "$dir/bin/spoolway" "$@" < /dev/null > "$dir/$side/$cmd.out" 2>&1) || status=$?
      else
        (cd "$consumer" && env "${unset_args[@]}" timeout 300 spoolway "$@" < /dev/null > "$dir/$side/$cmd.out" 2>&1) || status=$?
      fi
      echo "$status" > "$dir/$side/$cmd.status"
    done
  done
  for cmd in sync-dry-run pipeline-check doctor-no-live; do
    old=$(cat "$dir/as-is/$cmd.status"); new=$(cat "$dir/to-be/$cmd.status")
    if [ "$old" = 0 ] && [ "$new" != 0 ]; then slug=new
    elif [ "$old" != 0 ] && [ "$new" = 0 ]; then slug=fixed
    elif [ "$old" != 0 ]; then slug=pre-existing
    elif cmp -s "$dir/as-is/$cmd.out" "$dir/to-be/$cmd.out"; then slug="same output"
    else slug="passes under both, output differs"; fi
    say "$cmd	as-is exit $old	to-be exit $new	$slug	$dir/as-is/$cmd.out $dir/to-be/$cmd.out"
  done
  say "saved under $dir; the cause of each difference is yours to read in the outputs"
}

# project_homes: every spoolway project home on this machine, one path per line.
project_homes() { local p; for p in "$HOME"/.spoolway/*/project.toml; do [ -f "$p" ] && dirname "$p"; done; return 0; }
proj_value() { { grep -E "^$2[[:space:]]*=" "$1" || true; } | head -n 1 | cut -d= -f2- | sed -E 's/^[[:space:]]*"?//; s/"?[[:space:]]*$//'; }
fm_value() { { sed -n '1,/^---$/{/^---$/!p}' "$1" | sed -n '2,$p'; } | { grep -E "^$2:" || true; } | head -n 1 | cut -d: -f2- | sed -E "s/^[[:space:]]*['\"]?//; s/['\"]?[[:space:]]*$//"; }

# queue-snapshot: per project home, each task, its state, lane, branch and unpushed commits.
queue_snapshot() {
  local out home root json id state lane doc wt branch base ahead
  scratch_root; out=$scratch/queue-snapshot.txt
  : > "$out"
  while IFS= read -r home; do
    root=$(proj_value "$home/project.toml" root)
    {
      say "project	$home	$root"
      if ! json=$(spw 60 queue list --json -C "$root" 2> /dev/null) || ! jq -e . > /dev/null 2>&1 <<<"$json"; then
        say "unreadable	$home	queue list --json failed for $root"; continue
      fi
      while IFS=$'\t' read -r id state; do
        lane=no; [ "$state" = running ] && lane=yes
        doc=$home/queue/$id.md; branch=; ahead=unknown; wt=
        if [ -f "$doc" ]; then
          branch=$(fm_value "$doc" branch); base=$(fm_value "$doc" base); wt=$(fm_value "$doc" worktree_path)
        fi
        if [ -n "$branch" ] && [ -n "$wt" ] && [ -d "$wt" ]; then
          if git -C "$wt" rev-parse -q --verify "refs/remotes/origin/$branch" > /dev/null; then
            ahead=$(git -C "$wt" rev-list --count "origin/$branch..HEAD" 2> /dev/null || echo unknown)
          elif git -C "$wt" rev-parse -q --verify "refs/remotes/origin/${base:-main}" > /dev/null; then
            ahead=$(git -C "$wt" rev-list --count "origin/${base:-main}..HEAD" 2> /dev/null || echo unknown)
          fi
        fi
        say "task	$id	$state	lane $lane	branch ${branch:-none}	unpushed commits $ahead"
      done < <(jq -r '.tasks[] | [.id, .state] | @tsv' <<<"$json")
    } >> "$out"
  done < <(project_homes)
  cat "$out"
  say "saved to $out"
}

# discover: the checkouts a spoolway version change touches, found from signals on disk, with
# what each runs on spoolway. Read-only; the rules are in discovery.md.
disc_key() { local k; k=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2> /dev/null) && { cd -P "$k/.." 2> /dev/null && pwd; } || printf '%s\n' "$1"; }

# disc_candidates: `<path>\t<source>` lines, one per finding, from the three sources.
disc_candidates() {
  local home root line repo
  printf '%s\t%s\n' "$consumer" "current checkout"
  while IFS= read -r home; do
    root=$(proj_value "$home/project.toml" root)
    [ -n "$root" ] && printf '%s\t%s\n' "$root" "registry $home"
  done < <(project_homes)
  if [ -f "$consumer/$PROJECTS" ]; then
    while IFS= read -r line; do
      repo=$(sed -nE 's/^\|[[:space:]]*`?([A-Za-z0-9_.-]+\/)?([A-Za-z0-9_.-]+)`?[[:space:]]*\|.*/\2/p' <<<"$line")
      case $repo in '' | Repository | ---*) continue ;; esac
      printf '%s\t%s\n' "$(dirname "$consumer")/$repo" "$PROJECTS names $(sed -E 's/^\|[[:space:]]*([^|]*[^|[:space:]])[[:space:]]*\|.*/\1/' <<<"$line")"
    done < "$consumer/$PROJECTS"
  fi
}

# disc_report <path> <sources>: one consumer's facts, tab-separated.
disc_report() {
  local c=$1 src=$2 home= h root pin p name rel hash h2 f d line json id state n
  say "consumer	$c	found by: $src"
  pin=$(sed -n 's/^revision //p' "$c/$LOCK" 2> /dev/null | head -n 1)
  say "pin	$c	${pin:-none: no $LOCK}"
  for p in "$c"/.spoolway/pipelines/*.yml; do
    [ -f "$p" ] || continue
    name=${p##*/}; rel=.spoolway/pipelines/$name
    hash=$(awk -F'\t' -v p="$rel" '$2 == p { split($1, a, " "); print a[2] }' "$c/$LOCK" 2> /dev/null)
    h2=$(awk -F'\t' -v p="$rel" '$2 == p { split($1, a, " "); print a[2] }' "$plugin_root/spoolway/types.manifest")
    if [ -z "$hash" ]; then say "pipeline	$c	${name%.yml}	own (not in the lock)"
    elif [ "$hash" = "$h2" ]; then say "pipeline	$c	${name%.yml}	companion (lock hash matches this revision's types)"
    else say "pipeline	$c	${name%.yml}	companion, another revision (lock hash differs from this revision's)"; fi
  done
  for d in "$c"/.spoolway/prompts/*/; do [ -d "$d" ] && say "prompt	$c	$(basename "$d")"; done
  if [ -f "$c/$SUBSET" ]; then say "subset	$c	present	$(grep -cvE '^[[:space:]]*(#|$)' "$c/$SUBSET" || true) paths"; else say "subset	$c	absent"; fi
  for h in $(project_homes); do
    root=$(proj_value "$h/project.toml" root)
    if [ -n "$root" ] && [ "$(disc_key "$root")" = "$(disc_key "$c")" ]; then home=$h; break; fi
  done
  if [ -z "$home" ]; then
    say "override	$c	none found: no registry project holds this checkout"
  else
    n=0
    for f in "$home"/overrides/*; do
      [ -f "$f" ] || continue
      n=1; say "override	$c	${f##*/}	$(grep -vE '^[[:space:]]*(#|$)' "$f" | head -n 3 | tr '\n' ';' | sed 's/;$//')"
    done
    [ $n = 1 ] || say "override	$c	none"
  fi
  while IFS= read -r line; do
    say "spoolway-pin	$c	$line"
  done < <(cd "$c" && grep -rnoE --exclude-dir=.git --exclude-dir=.scratch --exclude-dir=node_modules -e 'spoolway[-_ @/]*v?[0-9]+\.[0-9]+\.[0-9]+' -- .github scripts docs README.md CLAUDE.md 2> /dev/null | sed -E 's/^([^:]+:[0-9]+):.*[^0-9.]v?([0-9]+\.[0-9]+\.[0-9]+)$/\1	\2/' | LC_ALL=C sort -u)
  if [ -z "$home" ]; then say "task	$c	unreadable: no registry project holds this checkout"
  elif ! json=$(spw 60 queue list --json -C "$(proj_value "$home/project.toml" root)" 2> /dev/null) || ! jq -e . > /dev/null 2>&1 <<<"$json"; then
    say "task	$c	unreadable: queue list --json failed"
  else
    n=0
    while IFS=$'\t' read -r id state; do n=1; say "task	$c	$id	$state"; done < <(jq -r '.tasks[] | select(.state == "queued" or .state == "blocked") | [.id, .state] | @tsv' <<<"$json")
    [ $n = 1 ] || say "task	$c	none queued or blocked"
  fi
}

discover() {
  local path source key i found
  local -a keys=() paths=() srcs=()
  while IFS=$'\t' read -r path source; do
    key=$(disc_key "$path")
    found=-1
    for i in "${!keys[@]}"; do [ "${keys[$i]}" = "$key" ] && found=$i; done
    if [ $found -ge 0 ]; then srcs[found]="${srcs[$found]}; $source"; else keys+=("$key"); paths+=("$path"); srcs+=("$source"); fi
  done < <(disc_candidates)
  for i in "${!paths[@]}"; do
    path=${paths[$i]}
    if [ ! -d "$path" ]; then say "unreadable	$path	found by: ${srcs[$i]}	checkout gone: no such directory"
    elif ! git -C "$path" rev-parse --git-dir > /dev/null 2>&1; then say "unreadable	$path	found by: ${srcs[$i]}	not a git checkout"
    elif [ ! -d "$path/.spoolway" ]; then say "unreadable	$path	found by: ${srcs[$i]}	no .spoolway/ directory"
    elif [ ! -r "$path/.spoolway" ]; then say "unreadable	$path	found by: ${srcs[$i]}	no access to .spoolway/"
    else disc_report "$path" "${srcs[$i]}"; fi
  done
}

# salvage <task>: what a task's worktree holds that origin lacks, kept under ./.scratch/.
salvage() {
  local task=$1 home doc wt branch base dir f ahead
  for home in $(project_homes); do [ -f "$home/queue/$task.md" ] && { doc=$home/queue/$task.md; break; }; done
  [ -n "${doc:-}" ] || die "no task $task in any spoolway project home's queue"
  wt=$(fm_value "$doc" worktree_path); branch=$(fm_value "$doc" branch); base=$(fm_value "$doc" base)
  [ -d "$wt" ] || die "the worktree $wt of $task is gone"
  scratch_root; dir=$scratch/salvage-$task
  rm -rf "$dir"; mkdir -p "$dir/logs"
  cp "$doc" "$dir/task.md"
  git -C "$wt" diff HEAD > "$dir/diff.patch"
  say "diff	$dir/diff.patch	$(wc -l < "$dir/diff.patch") lines"
  git -C "$wt" ls-files --others --exclude-standard -z > "$dir/untracked.list"
  if [ -s "$dir/untracked.list" ]; then
    tar -C "$wt" --null -T "$dir/untracked.list" -cf "$dir/untracked.tar"
    say "untracked	$dir/untracked.tar	$(tr -cd '\0' < "$dir/untracked.list" | wc -c) files"
  else say "untracked	none"; fi
  for f in "$home/commands/$task"*.log; do [ -f "$f" ] && cp "$f" "$dir/logs/"; done
  [ -d "$home/scratch/$task" ] && cp -a "$home/scratch/$task" "$dir/logs/scratch"
  say "logs	$dir/logs	$(find "$dir/logs" -type f | wc -l) files"
  if git -C "$wt" rev-parse -q --verify "refs/remotes/origin/$branch" > /dev/null; then ahead="origin/$branch..HEAD"; else ahead="origin/${base:-main}..HEAD"; fi
  if [ "$(git -C "$wt" rev-list --count "$ahead" 2> /dev/null || echo 0)" -gt 0 ]; then
    git -C "$wt" bundle create "$dir/$task.bundle" HEAD "^${ahead%..HEAD}" > /dev/null 2>&1 || die "git bundle create failed for $ahead"
    git -C "$wt" bundle verify "$dir/$task.bundle" > /dev/null 2>&1 || die "git bundle verify refused $dir/$task.bundle"
    say "bundle	$dir/$task.bundle	verified	$ahead"
  else say "bundle	none	no commits in $ahead"; fi
}

# fresh-id <id>…: whether task/<id> is absent from origin.
fresh_id() {
  local id out
  for id in "$@"; do
    out=$(git -C "$consumer" ls-remote --heads origin "task/$id") || die "git ls-remote origin failed"
    if [ -z "$out" ]; then say "$id	free	task/$id is absent from origin"; else say "$id	taken	task/$id exists on origin"; fi
  done
}

# --- main -------------------------------------------------------------------------------------

command -v jq > /dev/null || die "jq is not installed"
answers=
case "${1:-}" in
  detect) [ $# -le 2 ] || usage; consumer=$(consumer_dir "${2:-}"); detect ;;
  plan) [ $# -ge 2 ] && [ $# -le 3 ] || usage; answers=$(cd "$(dirname "$2")" && pwd)/$(basename "$2"); consumer=$(consumer_dir "${3:-}"); dry=1; apply ;;
  apply) [ $# -ge 2 ] && [ $# -le 3 ] || usage; answers=$(cd "$(dirname "$2")" && pwd)/$(basename "$2"); consumer=$(consumer_dir "${3:-}"); apply ;;
  labels) [ $# -ge 2 ] && [ $# -le 3 ] || usage; labels "$2" "${3:-}" ;;
  bump) [ $# -ge 2 ] && [ $# -le 3 ] || usage; consumer=$(consumer_dir "${3:-}"); bump "$2" ;;
  memex) [ $# -eq 3 ] && { [ "$2" = plan ] || [ "$2" = apply ]; } || usage; answers=$(cd "$(dirname "$3")" && pwd)/$(basename "$3"); [ -f "$answers" ] || die "no answers file $answers"; [ "$2" = plan ] && dry=1; memex_apply ;;
  spoolway-version) [ $# -le 2 ] || usage; consumer=$(consumer_dir); spoolway_version "${2:-}" ;;
  gap) [ $# -eq 2 ] || usage; consumer=$(consumer_dir); gap "$2" ;;
  probe) [ $# -eq 2 ] || usage; consumer=$(consumer_dir); probe "$2" ;;
  probe-run) [ $# -le 2 ] || usage; consumer=$(consumer_dir); probe_run "${2:-}" ;;
  queue-snapshot) [ $# -eq 1 ] || usage; consumer=$(consumer_dir); queue_snapshot ;;
  discover) [ $# -eq 1 ] || usage; consumer=$(consumer_dir); discover ;;
  salvage) [ $# -eq 2 ] || usage; consumer=$(consumer_dir); salvage "$2" ;;
  fresh-id) [ $# -ge 2 ] || usage; consumer=$(consumer_dir); shift; fresh_id "$@" ;;
  *) usage ;;
esac
