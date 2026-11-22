#!/usr/bin/env bash
# The spoolway pipeline types, written from this plugin into a consumer's tracked setup. Every
# consumer runs the same types at the revision it recorded, so a fix lands once, here.
#
#   types.sh manifest            print the manifest of types/ (types.manifest is this, committed)
#   types.sh write [<consumer>]  write types/ into the consumer (default: the current git
#                                checkout) and record the revision in .spoolway/plugin.lock
#
# types/ mirrors the consumer path for path, with one rename: types/setup/ is the consumer's
# .spoolway/. A nested .spoolway/ would be refused once this repo is a spoolway project itself.
#
# `write` takes its revision from the install record of the copy it runs from and records it in
# .spoolway/plugin.lock: the lock is the only place a consumer names the revision it took, and it
# reads nothing from .claude/settings.json. It refuses, writing nothing, when this copy is not an
# installed plugin, does not match its own manifest, or when a path it would write or delete has
# uncommitted changes. A path the previous
# lock listed and this revision no longer ships is deleted. The lock holds no date, so writing
# the same revision twice changes nothing.
#
# A consumer that runs only some of the types declares them in .spoolway/types.subset, one
# consumer path per line ('#' starts a comment, blank lines are ignored). `write` then writes,
# locks and deletes only those paths: a path the previous lock listed and the subset no longer
# names is deleted, and a subset naming a path this revision does not ship is refused. Without
# the file every path is written, as before. The file is the consumer's own and is never written
# by this script.

set -euo pipefail

PLUGIN=spoolway-companion
MARKETPLACE=spoolway-companion
LOCK=.spoolway/plugin.lock
SUBSET=.spoolway/types.subset

here=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
types=$here/types
manifest=$here/types.manifest

die() { echo "spoolway-types: $*" >&2; exit 1; }
usage() { echo "usage: types.sh manifest | types.sh write [<consumer>]" >&2; exit 64; }

# consumer_path <path under types/>: the path it is written to.
consumer_path() { case "$1" in setup/*) echo ".spoolway/${1#setup/}" ;; *) echo "$1" ;; esac; }

# Manifest lines, sorted by consumer path, as git ls-tree writes them:
#   100644 <sha256>\t<path>    a file (100755 when executable)
#   120000 <target>\t<path>    a symbolic link
manifest() {
  [ -d "$types" ] || die "no types/ beside $0"
  (cd "$types" && find . \( -type f -o -type l \) -printf '%P\n') | LC_ALL=C sort | while IFS= read -r p; do
    src=$types/$p
    if [ -L "$src" ]; then
      printf '120000 %s\t%s\n' "$(readlink "$src")" "$(consumer_path "$p")"
    else
      mode=100644; [ -x "$src" ] && mode=100755
      printf '%s %s\t%s\n' "$mode" "$(sha256sum "$src" | cut -d' ' -f1)" "$(consumer_path "$p")"
    fi
  done | LC_ALL=C sort -t$'\t' -k2
}

# installed_revision: the commit of the install this copy is. The plugin root is this folder's
# parent; Claude Code records it as `installPath`, beside `gitCommitSha`.
installed_revision() {
  local root installed
  root=$(cd -P "$here/.." && pwd)
  installed=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json
  [ -f "$installed" ] || return 0
  jq -r --arg root "$root" '[.plugins[]?[]? | select(.installPath == $root) | .gitCommitSha // empty] | first // empty' "$installed"
}

# subset_paths <consumer>: the consumer paths .spoolway/types.subset names, in file order, with
# whole-line comments and blank lines dropped. Prints nothing when the consumer has no subset.
subset_paths() {
  local f=$1/$SUBSET
  [ -f "$f" ] || return 0
  { grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$f" || true; } \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

write() {
  local consumer=${1:-}
  if [ -z "$consumer" ]; then
    consumer=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git checkout; name the consumer"
  fi
  consumer=$(cd -P "$consumer" && pwd)
  git -C "$consumer" rev-parse --git-dir >/dev/null 2>&1 || die "$consumer is not a git checkout"
  command -v jq >/dev/null || die "jq is not installed"

  local rev
  rev=$(installed_revision)
  [ -n "$rev" ] || die "this copy ($here) is not an installed $PLUGIN plugin, so its revision is unknown; install it with \`claude plugin install $PLUGIN@$MARKETPLACE --scope user\`, restart Claude Code, and run this from the installed plugin"

  local full want subset missing note=""
  full=$(manifest)
  [ "$full" = "$(cat "$manifest")" ] || die "this copy does not match its own types.manifest; reinstall the plugin"

  # What this consumer takes: every path, or only the ones its .spoolway/types.subset names.
  want=$full
  if [ -f "$consumer/$SUBSET" ]; then
    subset=$(subset_paths "$consumer")
    [ -n "$subset" ] || die "$consumer/$SUBSET names no paths; remove the file to take every type"
    missing=$(LC_ALL=C comm -23 <(LC_ALL=C sort -u <<<"$subset") <(cut -f2 <<<"$full" | LC_ALL=C sort -u))
    [ -z "$missing" ] || die "$consumer/$SUBSET names paths this revision does not ship:
$missing"
    want=$(awk -F'\t' 'NR == FNR { keep[$0] = 1; next } $2 in keep' <(printf '%s\n' "$subset") - <<<"$full")
  fi

  # Paths this revision ships, and paths the previous lock listed that it no longer ships.
  local paths gone=""
  paths=$(cut -f2 <<<"$want")
  if [ -f "$consumer/$LOCK" ]; then
    gone=$(grep -E '^[0-9]{6} ' "$consumer/$LOCK" | cut -f2 | LC_ALL=C sort | LC_ALL=C comm -23 - <(LC_ALL=C sort <<<"$paths") || true)
  fi

  local dirty
  dirty=$(cd "$consumer" && { printf '%s\n' $paths $gone $LOCK; } | xargs git status --porcelain -- 2>/dev/null || true)
  [ -z "$dirty" ] || die "uncommitted changes on paths this would write or delete; commit or discard them first:
$dirty"

  local mode value p src dst
  while IFS=$'\t' read -r head p; do
    mode=${head%% *} value=${head#* }
    dst=$consumer/$p
    mkdir -p "$(dirname "$dst")"
    if [ -d "$dst" ] && [ ! -L "$dst" ]; then rm -rf "$dst"; fi
    if [ "$mode" = 120000 ]; then
      ln -sfn "$value" "$dst"
    else
      case "$p" in .spoolway/*) src=$types/setup/${p#.spoolway/} ;; *) src=$types/$p ;; esac
      rm -f "$dst"
      cp "$src" "$dst"
      chmod "${mode:3}" "$dst"
    fi
  done <<<"$want"
  for p in $gone; do
    rm -rf "${consumer:?}/$p"
    echo "deleted $p"
  done

  {
    echo "# Written by /$PLUGIN:spoolway-types from the $PLUGIN plugin at the revision below; do not edit by hand."
    echo "plugin $PLUGIN"
    echo "revision $rev"
    printf '%s\n' "$want"
  } > "$consumer/$LOCK"

  [ "$want" = "$full" ] || note=" ($SUBSET: $(wc -l <<<"$want") of $(wc -l <<<"$full") paths)"
  echo "wrote $(wc -l <<<"$want") path(s) of $PLUGIN ${rev:0:12} into $consumer and recorded them in $LOCK$note"
}

case "${1:-}" in
  manifest) [ $# -eq 1 ] || usage; manifest ;;
  write) [ $# -le 2 ] || usage; write "${2:-}" ;;
  *) usage ;;
esac
