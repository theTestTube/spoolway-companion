#!/usr/bin/env bash
# Page pins in the Developing and Materializing pipelines, for a consumer that keeps pages of prose
# citing its code: a run that changes a file a page cites answers for that page before its pull
# request is handed over, and the page's drift pin is moved by a command step, never by a lane.
#
# Only when `.spoolway/companion.env` (or the environment) names a pages directory:
#
#   PAGES_DIR             the directory of the pages, relative to the repository root. Unset, every
#                         mode says so and passes at once.
#   PAGES_GATE            the command that reports stale pages, in the record contract below
#                         (default `scripts/gates/run.sh stale-pages`). It reads STALE_PAGES_RECORDS,
#                         STALE_PAGES_SCOPE and STALE_PAGES_BASE.
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
# The gate is asked in records mode (`STALE_PAGES_RECORDS=1`): it prints one record per page,
# one line of TAB separated fields, and ends with `=== GREEN` or `=== RED`:
#
#   <slug> <pin> <pin-in-history> <deleted> <changed> <owed-by> <compile-proof>
#
# `slug` is the page file name without `.md`; `pin` is its 40-hex pin, or empty; `pin-in-history`
# is `true` or `false`; `deleted` and `changed` are the cited paths that were deleted or changed
# since the pin, `;` separated, empty when none; `owed-by` is `branch` (this branch made the page
# stale), `base` (only the base carries it, reported and never blocking) or `none` (not stale); and
# `compile-proof` is `yes`, `no` or `n/a`. A record is RED when `owed-by` is `branch` or `base`,
# GREEN when it is `none`. The closing line and the exit code answer for the branch: the gate exits 1
# (`=== RED`) when a record is owed by `branch`, and 0 (`=== GREEN`) when its red records are all
# owed by `base`. The `pin` step moves no pin on a page owed by `base`. The off-history flag and the compile proof are fields, so no gate
# message is ever read as a cited path. A gate that cannot speak the contract, or a repo with no
# wiki, names `scripts/spoolway/stale-pages-stub.sh` as PAGES_GATE.
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

# record_reason <record>: the reason a record is red, as prose, from the contract's fields alone.
# The off-history flag and the compile proof are fields here, never a cited path.
record_reason() {
  printf '%s\n' "$1" | awk -F'\t' '
    { why = ""
      if ($4 != "") why = "deleted: " $4
      if ($5 != "") why = why (why != "" ? "; " : "") "changed: " $5
      if ($3 == "false") why = why (why != "" ? "; " : "") "pin " substr($2, 1, 7) " is not in history"
      if ($7 == "no") why = why (why != "" ? "; " : "") "no compile proof"
      print (why != "" ? why : "red") }'
}

# gate <scope>: runs the stale-pages gate in records mode into $gate_out and $gate_rc. The gate
# reads STALE_PAGES_RECORDS and prints the record contract's one line per page, not prose.
gate() {
  gate_rc=0
  if [ "$1" = branch ]; then
    echo "$mode: STALE_PAGES_RECORDS=1 STALE_PAGES_SCOPE=branch STALE_PAGES_BASE=$base $PAGES_GATE"
    gate_out=$(STALE_PAGES_RECORDS=1 STALE_PAGES_SCOPE=branch STALE_PAGES_BASE=$base bash -c "$PAGES_GATE" 2>&1) || gate_rc=$?
  else
    echo "$mode: STALE_PAGES_RECORDS=1 $PAGES_GATE"
    gate_out=$(STALE_PAGES_RECORDS=1 env -u STALE_PAGES_SCOPE -u STALE_PAGES_BASE bash -c "$PAGES_GATE" 2>&1) || gate_rc=$?
  fi
}

# gate_summary: the red records of the last gate run, rendered as the contract's fields, and the
# gate's closing line.
gate_summary() {
  printf '%s\n' "$gate_out" | awk -F'\t' '
    /^=== (GREEN|RED) / { print; next }
    /^=== / { next }
    NF < 7 || ($6 != "branch" && $6 != "base") { next }
    { printf "--- stale-pages/%s\n", $1
      printf "  slug:           %s\n", $1
      printf "  pin:            %s\n", $2
      printf "  pin-in-history: %s\n", $3
      printf "  deleted:        %s\n", $4
      printf "  changed:        %s\n", $5
      printf "  owed-by:        %s\n", $6
      printf "  compile-proof:  %s\n", $7 }'
}

# reds: one record per red page of the last gate run, the contract's fields, one line per page.
# A record is red when it is owed by the branch or the base, green when owed by none.
reds() {
  printf '%s\n' "$gate_out" | awk -F'\t' 'NF >= 7 && ($6 == "branch" || $6 == "base") { print }'
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

# drift_paths <record>: the paths a red record names, one per line: its deleted and changed
# fields alone. The pin, the off-history flag and the compile proof are fields, never paths.
drift_paths() {
  printf '%s\n' "$1" | awk -F'\t' '
    { n = split($4, d, ";"); for (i = 1; i <= n; i++) if (d[i] != "") print d[i]
      n = split($5, c, ";"); for (i = 1; i <= n; i++) if (c[i] != "") print c[i] }'
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

# judge <record>: says what the record owes for one red page. Succeeds only when the page is
# declared `holds`, with a reason, at a commit since which none of its drifted paths changed, and
# when the record is owed by this branch: a red the base carries is reported and passes. `checks`
# and the `pin` step both ask it: a record that was true once is not enough.
judge() {
  local rec=$1 slug pin pin_history deleted changed owed proof
  local name read_cmd verdict commit why whole_rec whole_deleted reason
  local -a paths
  IFS=$'\037' read -r slug pin pin_history deleted changed owed proof \
    < <(printf '%s\n' "$rec" | tr '\t' '\037')
  name="stale-pages/$slug"
  reason=$(record_reason "$rec")
  if [ ! -f "$PAGES_DIR/$slug.md" ]; then
    echo "ENVIRONMENT: $mode: $name is red: $reason" >&2
    return 1
  fi
  # A red the base carries, not this branch: reported, never blocking. The gate says which side
  # owes it with `owed-by`, and the branch answers only for the reds it caused.
  if [ "$owed" = base ]; then
    echo "$mode: $slug is red from the base, not this branch: $reason. The base carries it; this branch owes nothing"
    return 0
  fi
  whole_rec=$(printf '%s\n' "$whole" | awk -F'\t' -v slug="$slug" '$1 == slug { print; exit }')
  whole_deleted=$(printf '%s\n' "$whole_rec" | cut -f4)
  mapfile -t paths < <({ drift_paths "$rec"; drift_paths "$whole_rec"; } | LC_ALL=C sort -u)
  if [ "${#paths[@]}" -eq 0 ]; then
    if [ "$proof" = no ]; then
      echo "$mode: $slug has no compile proof: $reason. Recompile it from a source it cites, commit, then record \`holds\` at that commit" >&2
      return 1
    fi
    # Red for its pin, not for a path. A branch that touched the page did it; otherwise the base carries it.
    if [ -n "$(git diff --name-only "$base" -- "$PAGES_DIR/$slug.md")" ]; then
      echo "$mode: $slug: $reason. This branch changed the page, and a lane never edits \`verified_commit\` or \`source_commit\`: undo that change (\`git show $base:$PAGES_DIR/$slug.md\` has the lines as they were); the \`pin\` step moves the pin after the handover" >&2
    else
      echo "ENVIRONMENT: $mode: $slug: $reason, and this branch did not touch the page" >&2
    fi
    return 1
  fi
  [ -n "$pin" ] || pin=$(page_pin "$slug")
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
  if [ -n "$deleted$whole_deleted" ]; then
    echo "$mode: $slug is declared holds and names a file that is gone ($reason). A page that cites a deleted file does not hold: record it \`no-longer-holds\` and block the task" >&2
    return 1
  fi
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
    n_red=$(reds | wc -l)
    if [ "$n_red" -gt 0 ]; then
      echo "$mode: $n_red red page(s) are reported, none owed by this branch"
    elif [ "$scope" = all ]; then
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
  while IFS= read -r rec; do
    judge "$rec" || owed=$((owed + 1))
  done < <(reds)
  if [ "$owed" -eq 0 ]; then
    echo "$mode: no red page is owed by this branch; the \`pin\` step moves the pins after the handover"
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

# merge_origin_base: when the base branch's remote moved and merging it into HEAD conflicts only
# in the pages' pin lines, merges it, keeping this branch's pins, so the pull request is
# mergeable again. A merge only happens on a conflict: a base that is behind but clean is left
# alone. Sets `merged=1` when it merged. Any other conflict fails the step: a person resolves it.
merge_origin_base() {
  local origin_branch ref rc
  merged=0
  origin_branch=$(task_starts_from "$task_file")
  origin_branch=${origin_branch:-$(task_base "$task_file")}
  ref=origin/$origin_branch
  git rev-parse -q --verify "$ref" > /dev/null || return 0
  rc=0
  merge_conflicts "$root" "$ref" || rc=$?
  if [ "$rc" -eq 1 ]; then return 0; fi
  [ "$rc" -eq 0 ] || exit 1
  if ! conflicts_only_pins "$root" "$conflict_tree" "$ref" "${conflict_files[@]}"; then
    echo "pin: merging $ref conflicts in more than the pages' pin lines; a person resolves it, then resumes:" >&2
    printf '  %s\n' "${conflict_files[@]}" >&2
    exit 1
  fi
  if ! git merge --no-edit -X ours "$ref" > /dev/null 2>&1; then
    echo "pin: merging $ref into $branch failed; nothing was pinned. Look at the worktree, then run the step again" >&2
    exit 1
  fi
  merged=1
  echo "pin: merged $ref, keeping this branch's pins"
}

merge_origin_base

# The base moved forward with the merge, so the pin and the squashed commit are read against it
# again. `branch_base` takes the nearest base, and the merge made the remote's tip an ancestor.
if ! base=$(branch_base "$root" "$task_file") || [ -z "$base" ]; then
  echo "ENVIRONMENT: pin: the branch this task was cut from resolves to no ref here; the stale-pages gate has no base to diff against" >&2
  exit 1
fi

# A merge commit is not the handover's squashed commit, so it needs its own branch below: the pin
# belongs on the merge commit (it carries the merged state), never on the pin commit that follows.
tip_parents=$(git rev-list --parents -n1 HEAD | wc -w)
mapfile -t commits < <(git rev-list --reverse "$base..HEAD")
if [ "${#commits[@]}" -eq 0 ]; then
  echo "pin: the branch holds no commit of its own; there is nothing to pin to" >&2
  exit 1
fi
target=${commits[0]}
if [ "$tip_parents" -ge 3 ]; then target=$(git rev-parse HEAD); fi

if [ "$tip_parents" -eq 2 ] && [ "${#commits[@]}" -ge 2 ] && only_pins "$(git rev-parse HEAD~1)" HEAD; then
  # A second run of this step: the pin commit is there already. Check it and push it.
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
fi
if [ "$tip_parents" -eq 2 ] && [ "${#commits[@]}" -ge 2 ]; then
  echo "pin: the branch holds ${#commits[@]} commits where the handover leaves one; nothing was pinned" >&2
  exit 1
fi

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
  while IFS= read -r rec; do
    if ! judge "$rec"; then
      refused=$((refused + 1))
    elif [ "$(printf '%s\n' "$rec" | cut -f6)" != base ]; then
      # A page the base owes was never declared: said by `judge`, never pinned.
      pages+=("$PAGES_DIR/${rec%%$'\t'*}.md")
    fi
  done < <(reds)
fi
if [ "$refused" -gt 0 ]; then
  restore
  echo "pin: $refused page(s) refused; nothing was pinned or pushed. A page that is not declared holds is never re-pinned: it needs a recompile, or its line in $record" >&2
  exit 1
fi

for page in "${pages[@]}"; do
  set_pins "$page" "verified_commit: $target" "verified: $(date +%F)"
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
if ! git commit -q -m "$PAGES_COMMIT_PREFIX move the drift pin of ${#moved[@]} page(s) to ${target:0:7}" \
  -m "Read against the change and declared still holding$audited; a pin the squashed commit carried is put back where the base has it:
$slugs" -- "${moved[@]}"; then
  restore
  echo "pin: the pin commit could not be made; the pages are as the handover left them" >&2
  exit 1
fi
trap - ERR
if [ "$(git rev-parse HEAD~1)" != "$target" ] || ! only_pins "$target" HEAD; then
  echo "pin: the commit just made is not a pin commit on $target; nothing was pushed" >&2
  exit 1
fi
if [ "${merged:-0}" = 1 ] && ! bash "$here/pins.sh" check "$scope"; then
  echo "pin: pins.sh check failed after merging the base; nothing was pushed. Read the pages it names, then run the step again" >&2
  exit 1
fi
push
echo "pin: ${#moved[@]} page(s) pinned or put back, ${#pages[@]} to $target, in $(git rev-parse --short HEAD), pushed to $branch"
full_gate
