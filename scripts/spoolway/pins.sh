#!/usr/bin/env bash
# Page pins in the Developing and Materializing pipelines, for a consumer that keeps pages of prose
# citing its code: a run that changes a file a page cites answers for that page before its pull
# request is handed over, and the page's drift pin is moved by a command step, never by a lane.
#
# Only when `.spoolway/companion.env` (or the environment) names a pages directory:
#
#   PAGES_DIR             the directory of the pages, relative to the repository root. Unset, every
#                         mode says so and passes at once.
#   PAGES_GATE            the command that reports stale pages, in the gate format below
#                         (default `scripts/gates/run.sh stale-pages`). It reads STALE_PAGES_SCOPE
#                         and STALE_PAGES_BASE.
#   PAGES_LOG             the log a page compile appends to (default: none, no edit-by-hand check).
#   PAGES_COMPILE_PATTERN the sed pattern that, at the start of a log line the branch added,
#                         precedes the compiled page names (default `## \[[0-9-]*\] compile | `).
#   PAGES_COMMIT_PREFIX   the subject prefix of the pin commit (default `docs(pages):`).
#
#   pins.sh status   what the gate says about this branch, and what the record says about each red
#                    page. Always exits 0: a lane runs it to see what it owes.
#   pins.sh check    the same, as the consumer's checks run it: exit 1 unless every red page is
#                    declared `holds` in the record, at a commit its cited paths have not changed since.
#   pins.sh pin      the `pin` step, after `handover`: one commit that moves `verified_commit` to
#                    the squashed commit and `verified:` to the day on the pages declared `holds`,
#                    and changes nothing else, then a plain push.
#
# The gate runs in branch scope (`STALE_PAGES_SCOPE=branch`): a task answers for the paths its
# branch changed, not for what its base already carries. A second argument `all` runs the full
# gate instead. That is Materializing: its `document` step is the one that writes the pages, so it
# answers for every stale page, it recompiles a page that no longer holds itself, and the `pin`
# step fails unless the full gate ends GREEN.
#
# The gate prints one block per check: a `--- <name>` line, then `  actual:   <text>` and
# `  verdict:  GREEN|RED`, and ends with `=== GREEN` or `=== RED`. A red page's actual names
# `deleted: <path>` or `changed: <path>[; ...]`, optionally followed by ` (since <commit>)`.
#
# The record is `stale-pages.md` in the task's scratch space, one line per page:
#
#   <page slug> | holds | <commit the page was read at> | <why the page still says what the code does>
#   <page slug> | no-longer-holds | <commit> | <what the page says that the change made false>
#
# The implementer writes it after reading `git diff <pin> -- <cited paths>` against the page, the
# `review` step audits every line, and the last line for a page wins. The paths are every cited
# path that changed since the pin, on this branch or before it: the pin is one per page. A page
# that names a deleted file cannot be declared `holds`. A page that no longer holds is never
# re-pinned as it stands: the implementer recompiles it, commits, and records `holds` at that commit.
#
# With PAGES_LOG set, a page this branch changed beyond its pin lines went through a compile when
# an entry the branch added to the log names it. One that no such entry names was edited by hand:
# `status` says so and `check` fails. That proves the entry, not that the compile ran: the
# `review` step reads the page.
#
# Why a step after `handover`: the pin belongs on a commit already on the branch, never the one
# that carries the page edit, and `spoolway stack` squashes the task into one commit. So the pin
# commit is the second commit of the branch, on top of the squashed one. `spoolway stack` squashes
# whatever the branch holds whenever it runs: a `handover` run again after this step folds the pin
# commit into a new squashed commit, and the pins then name a commit that is gone. This step moves
# them again when it follows; nothing else does.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

mode=${1:-}
scope=${2:-branch}
case $mode in
  status | check | pin) ;;
  *) echo "usage: pins.sh status | check | pin [all]" >&2; exit 64 ;;
esac
case $scope in
  branch | all) ;;
  *) echo "usage: pins.sh status | check | pin [all]" >&2; exit 64 ;;
esac
[ $# -le 2 ] || { echo "usage: pins.sh status | check | pin [all]" >&2; exit 64; }
# `status` and `check` write nothing and a lane runs them; `pin` commits and pushes.
[ "$mode" = pin ] && own_step pin pin

task_file=${SPOOLWAY_TASK_FILE:-}
cd "$root"

PAGES_DIR=$(companion_env PAGES_DIR)
PAGES_DIR=${PAGES_DIR#./}
PAGES_DIR=${PAGES_DIR%/}
if [ -z "$PAGES_DIR" ]; then
  echo "$mode: no pages directory is named (PAGES_DIR in .spoolway/companion.env), passing at once"
  exit 0
fi
PAGES_GATE=$(companion_env PAGES_GATE 'scripts/gates/run.sh stale-pages')
PAGES_LOG=$(companion_env PAGES_LOG)
PAGES_COMPILE_PATTERN=$(companion_env PAGES_COMPILE_PATTERN '## \[[0-9-]*\] compile | ')
PAGES_COMMIT_PREFIX=$(companion_env PAGES_COMMIT_PREFIX 'docs(pages):')

if [ "$mode" = pin ]; then
  for step in pin handover; do
    if step_skipped "$task_file" "$step"; then
      echo "pin: \`$step\` is named in skip_steps, passing at once"
      exit 0
    fi
  done
  # A trial arm publishes nothing (`spoolway stack` opens no pull request for it), and a task that
  # changed only its extra repositories was never stacked: neither has a squashed commit to pin to.
  if [ -n "$task_file" ] && [ -f "$task_file" ] && frontmatter_has_key "$task_file" trial; then
    echo "pin: a trial arm has no pull request, passing at once"
    exit 0
  fi
  if [ -n "$task_file" ] && [ -f "$task_file" ] && task_unchanged "$root" "$task_file"; then
    echo "pin: nothing changed in this repository, passing at once"
    exit 0
  fi
fi

if ! base=$(branch_base "$root" "$task_file") || [ -z "$base" ]; then
  echo "ENVIRONMENT: $mode: the branch this task was cut from resolves to no ref here; the stale-pages gate has no base to diff against" >&2
  [ "$mode" = status ] && exit 0
  exit 1
fi

record=
if [ -n "$task_file" ] && [ -f "$task_file" ] || [ -n "${SPOOLWAY_SCRATCH:-}" ]; then
  record=$(task_scratch "$task_file")/stale-pages.md
fi

# gate <scope>: runs the stale-pages gate into $gate_out and $gate_rc.
gate() {
  gate_rc=0
  if [ "$1" = branch ]; then
    echo "$mode: STALE_PAGES_SCOPE=branch STALE_PAGES_BASE=$base $PAGES_GATE"
    gate_out=$(STALE_PAGES_SCOPE=branch STALE_PAGES_BASE=$base bash -c "$PAGES_GATE" 2>&1) || gate_rc=$?
  else
    echo "$mode: $PAGES_GATE"
    gate_out=$(env -u STALE_PAGES_SCOPE -u STALE_PAGES_BASE bash -c "$PAGES_GATE" 2>&1) || gate_rc=$?
  fi
}

# gate_summary: the red checks of the last gate run, whole, and its closing line.
gate_summary() {
  printf '%s\n' "$gate_out" | awk '
    /^--- / { if (red) printf "%s", block; block = ""; red = 0 }
    /^=== (GREEN|RED) / { if (red) printf "%s", block; block = ""; red = 0; print; next }
    /^=== / { next }
    { block = block $0 "\n" }
    /^  verdict:  RED/ { red = 1 }
    END { if (red) printf "%s", block }'
}

# reds: one line per red check of the last gate run, <check name> TAB <its actual>.
reds() {
  printf '%s\n' "$gate_out" | awk '
    /^--- / { name = $2; actual = "" }
    /^  actual:   / { actual = substr($0, 13) }
    /^  verdict:  RED/ { print name "\t" actual }'
}

# declared <slug>: the record's last line for the page, as <verdict>, <commit> and <why> with a
# unit separator between them (`read` folds tabs, and an empty commit would shift the reason).
declared() {
  [ -n "$record" ] && [ -f "$record" ] || return 0
  awk -F'|' -v slug="$1" '
    function trim(s) { gsub(/^[ \t`]+|[ \t\r`]+$/, "", s); return s }
    trim($1) == slug && NF >= 2 {
      why = ""
      for (i = 4; i <= NF; i++) why = why (i > 4 ? "|" : "") $i
      line = trim($2) "\037" trim($3) "\037" trim(why)
    }
    END { if (line != "") print line }' "$record"
}

# page_pin <slug>: the page's pin, `verified_commit` when it carries one, else `source_commit`.
page_pin() {
  awk '
    $0 == "---" { if (++fences == 2) exit; next }
    fences == 0 { exit }
    index($0, "verified_commit:") == 1 { v = $0; sub(/^[^:]*:/, "", v); gsub(/[[:space:]"]/, "", v); verified = v }
    index($0, "source_commit:") == 1 { v = $0; sub(/^[^:]*:/, "", v); gsub(/[[:space:]"]/, "", v); source = v }
    END { print (verified != "" ? verified : source) }' "$PAGES_DIR/$1.md"
}

# drift_paths <actual>: the paths a red verdict names, one per line; nothing when the page is red
# for its pin and not for a path.
drift_paths() {
  case $1 in deleted:* | changed:*) ;; *) return 0 ;; esac
  printf '%s\n' "${1% (since *}" | tr ';' '\n' | sed -E 's/^ *(deleted|changed): //'
}

# whole_page_reds: runs the full gate once, after a red branch-scoped run, and keeps its red lines
# in $whole. A pin is one per page: moving it answers for every cited path that changed since,
# the ones the base already carried included, so those are read and judged too.
whole_page_reds() {
  if [ "$scope" = all ]; then whole=$(reds); return; fi
  local kept_out=$gate_out kept_rc=$gate_rc
  gate all
  whole=$(reds)
  gate_out=$kept_out gate_rc=$kept_rc
}

# judge <check name> <its actual>: says what the record owes for one red page. Succeeds only when
# the page is declared `holds`, with a reason, at a commit since which none of its drifted paths
# changed. `checks` and the `pin` step both ask it: a record that was true once is not enough.
judge() {
  local name=$1 actual=$2 slug=${1#stale-pages/} pin read_cmd verdict commit why whole_actual
  local -a paths
  if [ ! -f "$PAGES_DIR/$slug.md" ]; then
    echo "ENVIRONMENT: $mode: $name is red: $actual" >&2
    return 1
  fi
  whole_actual=$(printf '%s\n' "$whole" | awk -F'\t' -v name="$name" '$1 == name { print $2 }')
  mapfile -t paths < <({ drift_paths "$actual"; drift_paths "$whole_actual"; } | LC_ALL=C sort -u)
  if [ "${#paths[@]}" -eq 0 ]; then
    # Red for its pin. A branch that touched the page did it; otherwise the base carries it.
    if [ -n "$(git diff --name-only "$base" -- "$PAGES_DIR/$slug.md")" ]; then
      echo "$mode: $slug: $actual. This branch changed the page, and a lane never edits \`verified_commit\` or \`source_commit\`: undo that change (\`git show $base:$PAGES_DIR/$slug.md\` has the lines as they were); the \`pin\` step moves the pin after the handover" >&2
    else
      echo "ENVIRONMENT: $mode: $slug: $actual, and this branch did not touch the page" >&2
    fi
    return 1
  fi
  pin=$(page_pin "$slug")
  read_cmd="git diff $pin -- ${paths[*]}"
  IFS=$'\037' read -r verdict commit why < <(declared "$slug"; echo) || true
  case $verdict in
    "")
      echo "$mode: $slug is not in the record. Read \`$read_cmd\` against $PAGES_DIR/$slug.md, then add its line to $record" >&2
      return 1
      ;;
    no-longer-holds)
      echo "$mode: $slug is declared no-longer-holds ($why). It is never re-pinned as it stands: recompile it, commit, then record \`holds\` at that commit; if it cannot be recompiled from an issue or pull request export, block the task and name the page" >&2
      return 1
      ;;
    holds) ;;
    *)
      echo "$mode: the record's line for $slug says \"$verdict\": write \`holds\` or \`no-longer-holds\`" >&2
      return 1
      ;;
  esac
  case "$actual; $whole_actual" in
    *deleted:*)
      echo "$mode: $slug is declared holds and names a file that is gone (${whole_actual:-$actual}). A page that cites a deleted file does not hold: record it \`no-longer-holds\` and block the task" >&2
      return 1
      ;;
  esac
  if [ -z "$why" ]; then
    echo "$mode: $slug is declared holds with no reason: say why the page still holds, after reading \`$read_cmd\`" >&2
    return 1
  fi
  if ! git rev-parse -q --verify "$commit^{commit}" > /dev/null; then
    echo "$mode: $slug is declared holds at \"$commit\", which is no commit here: commit your work, read \`$read_cmd\`, and record \`git rev-parse HEAD\`" >&2
    return 1
  fi
  if ! git diff --quiet "$commit" -- "${paths[@]}"; then
    echo "$mode: $slug was declared holds at ${commit:0:7}, and its cited paths changed after that: read \`$read_cmd\` again and record the commit you read at" >&2
    return 1
  fi
  echo "$mode: $slug is declared holds at ${commit:0:7}: $why (read: \`$read_cmd\`)"
}

# no_red_named: a gate that failed and named no red check did not judge anything.
no_red_named() {
  [ -z "$(reds)" ] || return 0
  printf '%s\n' "$gate_out"
  echo "ENVIRONMENT: $mode: the stale-pages gate failed (exit $gate_rc) and named no red page" >&2
  [ "$mode" = status ] && exit 0
  exit 1
}

# without_pins: a page on stdin with the `verified_commit` and `verified` lines of its frontmatter
# taken out. The same lines in the body stay: they are prose there.
without_pins() {
  awk '
    $0 == "---" && fences < 2 { fences++; print; next }
    fences == 1 && (index($0, "verified_commit:") == 1 || index($0, "verified:") == 1) { next }
    { print }'
}

# by_hand: says, for each page this branch changed beyond its pin lines, which compile entry the
# branch added to PAGES_LOG names it, and counts in $hand the pages none names. No log, no check.
by_hand() {
  local page slug compiled
  hand=0
  [ -n "$PAGES_LOG" ] || return 0
  compiled=$(git diff "$base" HEAD -- "$PAGES_LOG" | sed -n "s/^+$PAGES_COMPILE_PATTERN//p")
  while IFS= read -r page; do
    slug=$(basename "$page" .md)
    [ -n "$page" ] && [ "$slug" != _index ] || continue
    if git cat-file -e "$base:$page" 2> /dev/null \
      && cmp -s <(git show "$base:$page" | without_pins) <(git show "HEAD:$page" | without_pins); then
      continue
    fi
    if printf '%s\n' "$compiled" | grep -q -E "(^|[^a-z0-9-])$slug([^a-z0-9-]|$)"; then
      echo "$mode: $slug changed on this branch, named by a compile entry this branch added to $PAGES_LOG"
    else
      echo "$mode: $slug changed on this branch and no compile entry this branch added to $PAGES_LOG names it: an edit by hand. Recompile it, or undo the change (\`git show $base:$page\`)" >&2
      hand=$((hand + 1))
    fi
  done < <(git diff --name-only --diff-filter=d "$base" HEAD -- "$PAGES_DIR")
}

# --- status and check ---------------------------------------------------------------------------

if [ "$mode" != pin ]; then
  by_hand
  gate "$scope"
  if [ "$gate_rc" -eq 0 ]; then
    gate_summary
    if [ "$scope" = all ]; then
      echo "$mode: no page cites a path that was deleted or changed since its pin"
    else
      echo "$mode: no page cites a path this branch changed, or every such page is unchanged since its pin"
    fi
    if [ "$hand" -gt 0 ]; then
      echo "$mode: $hand page(s) edited by hand" >&2
      [ "$mode" = status ] && exit 0
      exit 1
    fi
    exit 0
  fi
  if [ "$gate_rc" -ne 1 ]; then
    printf '%s\n' "$gate_out"
    echo "ENVIRONMENT: $mode: the stale-pages gate did not run (exit $gate_rc)" >&2
    [ "$mode" = status ] && exit 0
    exit 1
  fi
  gate_summary
  no_red_named
  whole_page_reds
  owed=$hand
  while IFS=$'\t' read -r name actual; do
    judge "$name" "$actual" || owed=$((owed + 1))
  done < <(reds)
  if [ "$owed" -eq 0 ]; then
    echo "$mode: every red page is declared holds; the \`pin\` step moves the pins after the handover"
    exit 0
  fi
  echo "$mode: $owed page(s) still owed" >&2
  [ "$mode" = status ] && exit 0
  exit 1
fi

# --- pin ----------------------------------------------------------------------------------------

branch=$(git rev-parse --abbrev-ref HEAD)
if [ -n "$(git status --porcelain)" ]; then
  echo "pin: the worktree has uncommitted changes after the handover; nothing was pinned" >&2
  exit 1
fi

# pin_line <key>: that frontmatter line of the page on stdin, whole, or nothing.
pin_line() {
  awk -v key="$1" '
    $0 == "---" { if (++fences == 2) exit; next }
    fences == 0 { exit }
    index($0, key ":") == 1 { print; exit }'
}

# last_byte: the last byte on stdin, in hex. `awk` ends every line it prints with a newline, so a
# page that has none at its end is told apart by this and by nothing `awk` writes.
last_byte() { tail -c1 | od -An -tx1 | tr -d ' \n'; }

# set_pins <page> <verified_commit line> <verified line>: writes the two frontmatter lines into
# the page, in place where it has them and before the closing fence where it has not. An empty
# line takes the page's own out. The page ends as it ended: with a newline, or without one.
set_pins() {
  awk -v commit="$2" -v day="$3" '
    $0 == "---" && fences < 2 {
      if (++fences == 2) {
        if (!has_commit && commit != "") print commit
        if (!has_day && day != "") print day
      }
      print; next
    }
    fences == 1 && index($0, "verified_commit:") == 1 { if (commit != "") print commit; has_commit = 1; next }
    fences == 1 && index($0, "verified:") == 1 { if (day != "") print day; has_day = 1; next }
    { print }' "$1" > "$1.pin"
  if [ "$(last_byte < "$1")" = 0a ]; then cat "$1.pin" > "$1"; else head -c -1 "$1.pin" > "$1"; fi
  rm -f "$1.pin"
}

# only_pins [<from> <to>]: succeeds when the diff (the worktree against the index when no commits
# are given, and the index is HEAD here) touches pages alone and, in them, the
# `verified_commit` and `verified` lines of the frontmatter alone, each left well formed, with the
# file's mode as it was. `source_commit` is provenance and never moves.
only_pins() {
  local from=${1:-HEAD} to=${2:-} outside file
  outside=$(git diff --name-only "$@" | grep -v -E "^$PAGES_DIR/[^/]+\.md$" || true)
  if [ -n "$outside" ]; then
    echo "pin: the pin commit would change more than pages: $outside" >&2
    return 1
  fi
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    after() { if [ -n "$to" ]; then git show "$to:$file" 2> /dev/null; else cat "$file" 2> /dev/null; fi; }
    if ! cmp -s <(git show "$from:$file" 2> /dev/null | without_pins) <(after | without_pins) \
      || [ "$(git show "$from:$file" 2> /dev/null | last_byte)" != "$(after | last_byte)" ] \
      || [ -n "$(git diff --raw "$@" -- "$file" | awk 'substr($1, 2) != $2')" ]; then
      echo "pin: the pin commit would change more of $file than the \`verified_commit\` and \`verified:\` lines of its frontmatter:" >&2
      git diff "$@" -- "$file" | grep -E '^([+-]|old mode|new mode)' | grep -v -E '^(\+\+\+|---) ' >&2 || true
      return 1
    fi
    if [ "$(after | awk '
        $0 == "---" { if (++fences == 2) exit; next }
        fences == 1 && index($0, "verified_commit:") == 1 { commits++; if ($0 !~ /^verified_commit: [0-9a-f]+$/ || length($0) != 57) bad = 1 }
        fences == 1 && index($0, "verified:") == 1 { days++; if ($0 !~ /^verified: [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) bad = 1 }
        END { print (bad || commits > 1 || days > 1) ? "bad" : "ok" }')" != ok ]; then
      echo "pin: $file would not carry one well-formed \`verified_commit\` and one \`verified:\` line" >&2
      return 1
    fi
  done < <(git diff --name-only "$@")
}

# full_gate: the whole gate, for the log. Red for pages this branch did not touch is said and
# does not fail the step: a task answers for what it broke. With `all`
# the task answers for every page, so a red full gate fails the step.
full_gate() {
  gate all
  gate_summary
  [ "$gate_rc" -ne 0 ] || return 0
  if [ "$scope" = all ]; then
    echo "pin: the full gate is RED after the pin, and this pipeline answers for every page" >&2
    exit 1
  fi
  echo "pin: the full gate is RED for pages this branch did not touch. Not this task's: the base it was cut from carries them"
}

push() {
  if ! git push origin "HEAD:refs/heads/$branch"; then
    echo "pin: the push was refused; the pin commit is on the local branch only. Nothing is forced: fetch, look at what arrived, then run the step again" >&2
    exit 1
  fi
}

mapfile -t commits < <(git rev-list --reverse "$base..HEAD")
squashed=${commits[0]:-}
case ${#commits[@]} in
  0)
    echo "pin: the branch holds no commit of its own; there is nothing to pin to" >&2
    exit 1
    ;;
  1) ;;
  2)
    # A second run of this step: the pin commit is there already. Check it and push it.
    only_pins "$squashed" HEAD || exit 1
    gate "$scope"
    gate_summary
    if [ "$gate_rc" -ne 0 ]; then
      echo "pin: the branch already carries a pin commit and the gate is still RED" >&2
      exit 1
    fi
    push
    echo "pin: the pin commit $(git rev-parse --short HEAD) was already on the branch; pushed"
    full_gate
    exit 0
    ;;
  *)
    echo "pin: the branch holds ${#commits[@]} commits where the handover leaves one; nothing was pinned" >&2
    exit 1
    ;;
esac

restore() { git checkout -q -- "$PAGES_DIR"; }
trap 'restore' ERR

# Whatever the squashed commit did to a page's pin lines is undone first, so each page is judged
# from the pin its base has: an earlier pin commit that a second `handover` folded in names a
# commit that is gone, and a pin a lane moved was never this step's. The page's body is left as
# the branch has it.
while IFS= read -r page; do
  [ -n "$page" ] && [ -f "$page" ] || continue
  git cat-file -e "$base:$page" 2> /dev/null || continue
  set_pins "$page" "$(git show "$base:$page" | pin_line verified_commit)" "$(git show "$base:$page" | pin_line verified)"
done < <(git diff --name-only "$base" HEAD -- "$PAGES_DIR")

gate "$scope"
if [ "$gate_rc" -gt 1 ]; then
  printf '%s\n' "$gate_out"
  restore
  echo "ENVIRONMENT: pin: the stale-pages gate did not run (exit $gate_rc)" >&2
  exit 1
fi
gate_summary
pages=() refused=0
if [ "$gate_rc" -eq 1 ]; then
  if [ -z "$(reds)" ]; then restore; fi
  no_red_named
  whole_page_reds
  while IFS=$'\t' read -r name actual; do
    if judge "$name" "$actual"; then
      pages+=("$PAGES_DIR/${name#stale-pages/}.md")
    else
      refused=$((refused + 1))
    fi
  done < <(reds)
fi
if [ "$refused" -gt 0 ]; then
  restore
  echo "pin: $refused page(s) refused; nothing was pinned or pushed. A page that is not declared holds is never re-pinned: it needs a recompile, or its line in $record" >&2
  exit 1
fi

for page in "${pages[@]}"; do
  set_pins "$page" "verified_commit: $squashed" "verified: $(date +%F)"
done
mapfile -t moved < <(git diff --name-only -- "$PAGES_DIR")
if [ "${#moved[@]}" -eq 0 ]; then
  echo "pin: no page is stale for this branch; nothing to pin"
  full_gate
  exit 0
fi

if ! only_pins; then
  restore
  exit 1
fi
gate "$scope"
if [ "$gate_rc" -ne 0 ]; then
  gate_summary
  restore
  echo "pin: the gate is still RED with the pins on $squashed; nothing was committed" >&2
  exit 1
fi

slugs=$(printf '%s\n' "${moved[@]}" | sed -E 's#.*/([^/]+)\.md$#- \1#')
audited=", each one audited by the review step"
[ "$scope" = all ] && audited=" by the document step"
if ! git commit -q -m "$PAGES_COMMIT_PREFIX move the drift pin of ${#moved[@]} page(s) to ${squashed:0:7}" \
  -m "Read against the change and declared still holding$audited; a pin the squashed commit carried is put back where the base has it:
$slugs" -- "${moved[@]}"; then
  restore
  echo "pin: the pin commit could not be made; the pages are as the handover left them" >&2
  exit 1
fi
trap - ERR
if [ "$(git rev-parse HEAD~1)" != "$squashed" ] || ! only_pins "$squashed" HEAD; then
  echo "pin: the commit just made is not a pin commit on $squashed; nothing was pushed" >&2
  exit 1
fi
push
echo "pin: ${#moved[@]} page(s) pinned or put back, ${#pages[@]} to $squashed, in $(git rev-parse --short HEAD), pushed to $branch"
full_gate
