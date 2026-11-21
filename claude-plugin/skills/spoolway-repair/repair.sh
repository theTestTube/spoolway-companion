#!/usr/bin/env bash
# The mechanical half of the spoolway-repair skill: every read of a doomed task, the first write,
# and the two roads out. The skill decides what the reads mean for the person; this script only
# gathers and concludes, so the same conclusions replay offline against a fixture
# (tests/spoolway-repair.test.sh). It resumes, unqueues, pushes and posts nothing: it prints the
# command for the person to rule on, and writes drafts.
#
#   repair.sh diagnose <task>   read-only; prints one JSON object (see the keys under `diag` below)
#   repair.sh salvage  <task>   the first write: copies the task's scratch space, its command-step
#                               logs and its document into <main checkout>/.scratch/spoolway/<task>/,
#                               drafts one file per handoff note that asks a person to post or open
#                               something, and prints one JSON object listing every copy. While the
#                               task stands on `blocked` it also keeps the diagnosis there, as
#                               first-diagnosis.json; a later salvage never replaces it.
#   repair.sh choose   <task>   read-only; the recommended road, advance or retreat, with its reason
#                               and its conditions, and the step an advance resumes at
#   repair.sh advance  <task> [<step>] [--confirmed "<the person's words>"]
#                               read-only but for one draft; the resume command at <step> (default:
#                               the recommended step) with its status-log message, or why it is
#                               refused. A step past a judgment that has not passed is the one-way
#                               door: no command until salvage is complete and --confirmed is given.
#   repair.sh retreat  <task>   the retreat's steps in order: the commit of loose work, the push, the check, the plain unqueue
#                               as commands; refused while a dispatcher runs. Writes one draft.
#   repair.sh pushed   <task>   read-only; whether the remote branch holds every commit of the local
#                               one, with nothing left uncommitted in the worktree; with the local
#                               branch deleted by the unqueue, whether the remote stands at or past
#                               the tip the first diagnosis saw.
#   repair.sh record   <task> <advance|retreat|door>
#                               drafts the comment for the bound issue, the pull request's repair
#                               section, and one finding per pipeline or task-document defect. The
#                               cause is the one first-diagnosis.json holds, whatever the task's
#                               stage is by then.
#
# A refusal prints the JSON object, with `refused` saying why, and exits 1; a task spoolway does not
# hold is one (`unknown-task`). A call that cannot be read at all (usage, a malformed id, a step the
# pipeline lacks, no checkout or project home) prints one line on stderr and exits 2. `salvage` has
# stops of its own: exit 3 and one line when its folder is not git-ignored, exit 1 with `ok: false`
# or one line when a copy cannot be made. `pushed` exits 1 with `ok: false` until the remote has all.
#
# Environment: REPAIR_REPO (default: the current directory) names the repo whose spoolway project
# holds the task. REPAIR_MESSAGE replaces the status-log message `advance` proposes.
#
# Formats are read from the binary, never restated here: the task document comes from
# `spoolway queue show`, the effective pipeline (overrides included) from `spoolway pipeline show`,
# the project's home from `spoolway task contract`, the dispatcher from `spoolway queue list`. The
# task document's own layout is `spoolway task contract`; the log lines read here are spoolway's own
# words in the Status Log. A command is printed only after its flags are found in the binary's own
# `--help`, at run time.
#
# Two conventions of the shipped Developing pipeline are read as well: the `skip_steps` and `implementer` keys of the Developing task document name steps
# that pass at once, and `close_on_merge: false` is the keep-open marker of a task bound to a spec.
set -euo pipefail

die() { printf 'repair: %s\n' "$*" >&2; exit "${2:-1}"; }
usage() { sed -n '2,39p' "$0" >&2; exit 2; }

repo=${REPAIR_REPO:-$PWD}
sp() { spoolway -C "$repo" "$@"; }

# ---------------------------------------------------------------------------------------------
# jq library: a task document and a pipeline listing in, conclusions out.
# ---------------------------------------------------------------------------------------------
read -r -d '' JQ_LIB <<'JQ' || true
def unq: sub("^'(?<x>.*)'$"; "\(.x)") | sub("^\"(?<x>.*)\"$"; "\(.x)");
def trim: sub("^\\s+"; "") | sub("\\s+$"; "");

# Frontmatter: top-level scalars, flow lists, and one level of block map or block list.
def frontmatter($fm):
  reduce $fm[] as $ln ({o: {}, cur: null};
    if ($ln | test("^[A-Za-z_][A-Za-z0-9_-]*:")) then
      ($ln | capture("^(?<k>[^:]+):[ ]*(?<v>.*)$")) as $m
      | if $m.v == "" then .cur = $m.k | .o[$m.k] = null
        elif ($m.v | test("^\\[.*\\]$")) then
          .cur = null | .o[$m.k] = ($m.v | .[1:-1] | split(",") | map(trim | unq) | map(select(. != "")))
        else .cur = null | .o[$m.k] = ($m.v | unq) end
    elif (.cur != null and ($ln | test("^\\s*- "))) then
      .o[.cur] = ((.o[.cur] // []) + [$ln | sub("^\\s*- "; "") | unq])
    elif (.cur != null and ($ln | test("^\\s+[^\\s:]+:"))) then
      ($ln | capture("^\\s+(?<k>[^:]+):[ ]*(?<v>.*)$")) as $m
      | .o[.cur] = ((.o[.cur] // {}) + {($m.k): ($m.v | unq)})
    else . end) | .o;

# The lines of a `## <name>` section, up to the next `## ` heading.
def section($body; $name):
  ($body | to_entries | map(select(.value | test("^## " + $name + "\\s*$"))) | .[0].key) as $s
  | if $s == null then []
    else $body[($s + 1):]
      | ((to_entries | map(select(.value | test("^## "))) | .[0].key) as $e | if $e == null then . else .[:$e] end)
    end;

# Handoff notes: `- `step` — text`. A note is addressed to a person when it says so; it asks for a
# draft when it also asks to post or open something.
def handoff_notes($body):
  [section($body; "Handoff")
    | reduce .[] as $ln ([];
        if ($ln | test("^- `[^`]+` — ")) then . + [$ln]
        elif length > 0 and ($ln | test("\\S")) and ($ln | test("^- ") | not) then .[-1] += "\n" + $ln
        else . end)
    | .[] | capture("^- `(?<step>[^`]+)` — (?<text>(?s).*)$")]
  | to_entries
  | map(.value + {n: (.key + 1)}
        | . + {to_person: (.text | test("for a person|needs a person|a person (must|may|has to|should|who)|before the task ends"; "i"))}
        | . + {asks: (if .to_person
                      then [.text | match("\\b([Pp]ost|[Oo]pen)\\s+(the|a|an|this|that|it|them|one|each|[\"\u0027`#])|\\b(posted|opened)\\b"; "g")
                                  | (.captures[0].string // .captures[2].string // .string) | ascii_downcase | sub("ed$"; "")]
                           | map(select(. == "post" or . == "open")) | unique
                      else [] end)});

# An acceptance criterion is a top-level bullet, a checkbox or a plain one (the Developing task
# template writes plain ones); an indented line under it belongs to it. It cannot pass when a note
# cites it by number and says only a person can act on it: the lane may not build it, and review
# cannot waive it.
def criteria($body; $notes):
  (section($body; "Acceptance criteria")
    | reduce .[] as $ln ([];
        if ($ln | test("^- ")) then . + [$ln | sub("^- (\\[[ xX]\\] )?"; "")]
        elif length > 0 and ($ln | test("^\\s+\\S")) then .[-1] += "\n" + ($ln | trim)
        else . end))
  | to_entries
  | map((.key + 1) as $n | .value as $text
        | [$notes[] | select(.text | test("criterion " + ($n | tostring) + "\\b"; "i"))
                    | select(.text | test("only a person|cannot waive|a person amends|person who wants"; "i"))] as $ev
        | {n: $n, text: $text, passable: ($ev | length == 0),
           reason: (if ($ev | length) == 0 then "no handoff note says a person must act before it can pass"
                    else "handoff note \($ev[0].n) (`\($ev[0].step)`) cites it and says only a person can act on it" end),
           evidence: [$ev[].n]});

def parse_all:
  split("\n") as $l
  | ([range(0; $l | length) | select($l[.] == "---")]) as $d
  | $l[($d[0] + 1):$d[1]] as $fm
  | $l[($d[1] + 1):] as $body
  | handoff_notes($body) as $notes
  | {fm: frontmatter($fm),
     log: [section($body; "Status Log")[] | select(startswith("- "))],
     notes: $notes,
     criteria: criteria($body; $notes)};

# `spoolway pipeline show`: per pipeline, per step, its `loop=` and where pass and fail go.
def parse_pipelines:
  split("\n")
  | reduce .[] as $ln ({p: null, s: null, o: {}};
      if ($ln | test("^pipeline `")) then
        ($ln | capture("^pipeline `(?<n>[^`]+)`")) as $m | .p = $m.n | .s = null | .o[$m.n] = {}
      elif (.p != null and ($ln | test("^  \\S+\\s+(agent|command)\\b"))) then
        ($ln | capture("^  (?<id>\\S+)\\s+(?<kind>agent|command)\\b(?<rest>.*)$")) as $m
        | .s = $m.id
        | .o[.p][$m.id] = {kind: $m.kind, loop: (($m.rest | capture("\\bloop=(?<l>[0-9]+)")? | .l | tonumber) // null)}
      elif (.s != null and ($ln | test("^\\s+pass -> "))) then
        ($ln | capture("^\\s+pass -> (?<pass>.*?)\\s+fail(/[a-z/]+)? -> (?<fail>.*)$")) as $m
        | .o[.p][.s] += {pass: $m.pass, fail: $m.fail}
      else . end)
  | .o;

# A step that passes at once, doing no work: the task skips it, or names the other implementer.
def passes_at_once($doc; $s):
  (($doc.skip_steps // []) | any(. == $s))
  or (($s == "implement" or $s == "implement-spec") and (($doc.implementer // "implement") != $s));
JQ

# ---------------------------------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------------------------------
[ $# -ge 2 ] || usage
command=$1 task=$2; shift 2
step='' confirmed='' road=''
case "$command" in
  diagnose | salvage | choose | retreat | pushed) [ $# -eq 0 ] || usage ;;
  advance)
    while [ $# -gt 0 ]; do
      case $1 in
        --confirmed) [ $# -ge 2 ] || usage; confirmed=$2; shift 2 ;;
        -*) usage ;;
        *) [ -z "$step" ] || usage; step=$1; shift ;;
      esac
    done ;;
  record)
    [ $# -eq 1 ] || usage
    road=$1
    case $road in advance | retreat | door) ;; *) usage ;; esac ;;
  *) usage ;;
esac
# A task id holds only lowercase letters, digits and hyphens (`spoolway task contract`, field `id`).
[[ $task =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || die "\`$task\` is not a task id (lowercase letters, digits and hyphens)" 2

main_checkout=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || die "$repo is not inside a git checkout" 2
main_checkout=$(dirname "$main_checkout")

pending=$(sp task contract 2>/dev/null | jq -r '.output.dir // empty' 2>/dev/null || true)
[ -n "$pending" ] || die "cannot read the project home from \`spoolway task contract\`" 2
[ "$(basename "$pending")" = pending ] || die "\`spoolway task contract\` names $pending as the pending directory, not <home>/pending" 2
home=$(dirname "$pending")

dest=$main_checkout/.scratch/spoolway/$task
first_file=$dest/first-diagnosis.json
unknown_task() { jq -n --arg task "$task" '{task: $task, refused: ["unknown-task"]}'; exit 1; }

# The document as spoolway holds it. Once a road is taken spoolway may hold it no longer, or hold it
# stripped of the keys that name the branch (the unqueue does that): `pushed` and `record` then
# read the copy salvage kept.
document_source=spoolway
if ! doc=$(sp queue show "$task" 2>/dev/null) || ! grep -q '^branch:' <<<"$doc"; then
  case $command in
    pushed | record) [ -f "$dest/task.md" ] || unknown_task ;;
    *) [ -n "$doc" ] || unknown_task ;;
  esac
  if [ -f "$dest/task.md" ] && { [ "$command" = pushed ] || [ "$command" = record ]; }; then
    doc=$(cat "$dest/task.md") document_source=salvage
  fi
fi
parsed=$(jq -R -s "$JQ_LIB parse_all" <<<"$doc") || die "\`$task\` is not a task document spoolway 0.6.0 writes (no frontmatter)" 2

# Files of the task's scratch space and its command-step logs, as `<relative name>\t<size>` lines
# under a root. Command logs are the home's `commands/<task> · <step>.<ext>` files.
scratch_files() {
  [ -d "$home/scratch/$task" ] || return 0
  find "$home/scratch/$task" -type f -printf '%P\t%s\n' | LC_ALL=C sort
}
command_files() {
  [ -d "$home/commands" ] || return 0
  find "$home/commands" -maxdepth 1 -type f -name "$task · *" -printf '%P\t%s\n' | LC_ALL=C sort
}

# ---------------------------------------------------------------------------------------------
# diagnose
# ---------------------------------------------------------------------------------------------
git_state() {  # <branch> <base_commit> <worktree path>
  local branch=$1 base=$2 wt=$3 exists=false commits='' remote_sha='' remote_state=unknown unpushed=null tree=null
  if git -C "$main_checkout" rev-parse --verify -q "refs/heads/$branch" >/dev/null; then
    exists=true
    commits=$(git -C "$main_checkout" log --format='%h %s' "$base..$branch" 2>/dev/null || true)
  fi
  if [ -d "$wt" ]; then
    tree=$(git -C "$wt" status --short | jq -R -s -c 'split("\n") | map(select(. != ""))')
  fi
  if [ -n "$branch" ] && remote=$(timeout 30 git -C "$main_checkout" ls-remote origin "refs/heads/$branch" 2>/dev/null); then
    remote_sha=${remote%%$'\t'*}
    if [ -z "$remote_sha" ]; then
      remote_state=absent
      [ "$exists" = true ] && unpushed=$(git -C "$main_checkout" rev-list --count "$base..$branch")
    else
      remote_state=present
      if [ "$exists" = true ] && git -C "$main_checkout" cat-file -e "$remote_sha^{commit}" 2>/dev/null; then
        unpushed=$(git -C "$main_checkout" rev-list --count "$remote_sha..$branch")
      fi
    fi
  fi
  jq -n --arg branch "$branch" --argjson exists "$exists" --arg commits "$commits" \
        --argjson tree "$tree" --arg wt "$wt" --argjson wt_present "$([ -d "$wt" ] && echo true || echo false)" \
        --arg rstate "$remote_state" --arg rsha "$remote_sha" --argjson unpushed "$unpushed" '
    {branch: $branch, local_branch_exists: $exists,
     commits_since_base: ($commits | split("\n") | map(select(. != ""))),
     worktree: {path: $wt, present: $wt_present, changes: $tree},
     remote: {branch: $rstate, sha: (if $rsha == "" then null else $rsha end), commits_not_on_remote: $unpushed}}'
}

dispatcher_state() {
  local q pid cmd mode source
  q=$(sp queue list --json 2>/dev/null || echo '{}')
  pid=$(jq -r '.dispatcher_pid // empty' <<<"$q")
  if [ -z "$pid" ] || [ ! -d "/proc/$pid" ]; then
    jq -n --arg pid "$pid" '{running: false, pid: null, mode: null, source: null, stale_pid: ($pid != "")}'
    return
  fi
  cmd=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)
  case "$cmd" in
    *--unattended*) mode=unattended source=flag ;;
    *--attended*) mode=attended source=flag ;;
    *)
      source=config
      if [ "$(sp config get unattended.enabled 2>/dev/null || echo false)" = true ]; then mode=unattended; else mode=attended; fi
      ;;
  esac
  jq -n --argjson pid "$pid" --arg mode "$mode" --arg source "$source" '{running: true, pid: $pid, mode: $mode, source: $source}'
}

read -r -d '' JQ_DIAG <<'JQ' || true
. as $p
| $p.fm as $fm
| ($fm.arrivals // {} | with_entries(.value |= tonumber)) as $arr
| ($pipelines[$fm.pipeline] // {}) as $in_force
| ($p.log) as $log
# The loop a refusal line states is the one the dispatcher applied. `spoolway pipeline show` gives
# the one in force now, which an override set since the dispatcher started can have changed; where
# a refusal line names a step, its value is the one counted against.
| (reduce ($log[] | capture("may not send this to `(?<step>[^`]+)` a [0-9]+[a-z]+ time — `[^`]+` has `loop: (?<loop>[0-9]+)`")?) as $m
     ({}; .[$m.step] = ($m.loop | tonumber))) as $stated
| ($in_force | with_entries(if $stated[.key] != null then .value.loop = $stated[.key] else . end)) as $steps
# Where `spoolway resume <task>` sends a blocked task, step by step, until a step does real work or
# a route into a spent loop is refused (and the task parks on `blocked` again).
| def route($cur; $chain):
    if ($chain | length) > 30 then {chain: $chain, outcome: "stalls", at: $cur, refused_at: null}
    elif passes_at_once($fm; $cur) then
      ($steps[$cur].pass // null) as $next
      | if $next == null or $steps[$next] == null then {chain: ($chain + [$cur]), outcome: "stalls", at: $cur, refused_at: null}
        elif $steps[$next].loop != null and (($arr[$next] // 0) >= $steps[$next].loop) then
          {chain: ($chain + [$cur]), outcome: "bounces", at: null, refused_at: $next}
        else route($next; $chain + [$cur]) end
    else {chain: ($chain + [$cur]), outcome: "runs", at: $cur, refused_at: null} end;
  ([range(0; $log | length) | select($log[.] | test("→ `blocked`"))] | last) as $bi
| (if $bi != null and $bi > 0 and ($log[$bi - 1] | test("may not send this to `[^`]+`")) then $log[$bi - 1] else null end) as $refusal_line
| ($refusal_line | if . == null then null else
    (capture("^- (?<at>\\S+ \\S+) `(?<from>[^`]+)` may not send this to `(?<step>[^`]+)` a (?<nth>[0-9]+)[a-z]+ time — `[^`]+` has `loop: (?<loop>[0-9]+)`")? // null) end) as $ref
| (if $fm.stage != "blocked" then
     {kind: "not-blocked", step: null, evidence: null,
      sentence: "Task `\($fm.id)` is on `\($fm.stage)`, not on `blocked`."}
   elif $ref != null then
     {kind: "spent-loop", step: $ref.step, from: $ref.from, loop: ($ref.loop | tonumber),
      arrivals: ($arr[$ref.step] // 0), evidence: $refusal_line,
      sentence: "Task `\($fm.id)` is parked on `blocked` because `\($ref.from)` was refused entry to `\($ref.step)`: its `loop: \($ref.loop)` is spent at \($arr[$ref.step] // 0) arrivals (\($ref.at))."}
   else
     ($log | map(select(test("→ `blocked`"))) | last // "") as $bl
     | {kind: "stopped-by-step", step: ($fm.blocked_from // null), evidence: $bl,
        sentence: "Task `\($fm.id)` is parked on `blocked`, stopped from `\($fm.blocked_from // "an unknown step")`; no refused route is logged, so the stop came from that step itself: \($bl)"}
   end) as $cause
| {
    task: $fm.id,
    spoolway: $spoolway_version,
    stage: $fm.stage,
    blocked_from: ($fm.blocked_from // null),
    pipeline: $fm.pipeline,
    cause: $cause,
    loops: [$steps | to_entries[] | select(.value.loop != null)
            | {step: .key, loop: .value.loop, arrivals: ($arr[.key] // 0), spent: (($arr[.key] // 0) >= .value.loop),
               loop_in_force: $in_force[.key].loop, loop_in_refusal: ($stated[.key] // null), dispatcher_applied: ($stated[.key] // null)}],
    last_refusal: ($log | map(select(test("may not send this to `[^`]+`"))) | last),
    plain_resume: (if $fm.stage == "blocked" and $fm.blocked_from != null then
        route($fm.blocked_from; []) | . + {step: $fm.blocked_from, passes_at_once: [.chain[] | select(passes_at_once($fm; .))]}
      else null end),
    handoff: {
      to_person: [$p.notes[] | select(.to_person) | {n, step, asks, text}],
      notes_total: ($p.notes | length)
    },
    criteria: $p.criteria,
    git: $git,
    scratch: $scratch,
    commands: $commands,
    dispatcher: $dispatcher,
    spec: (
      ($fm.close_on_merge != null or $fm.implementer == "implement-spec") as $bound
      | {bound: $bound, close_on_merge: ($fm.close_on_merge // null),
         keep_open_marker: (if $bound | not then "not-applicable" elif (($fm.close_on_merge // "") | ascii_downcase) == "false" then "present" else "missing" end)})
  }
JQ

to_files() { jq -R -s -c 'split("\n") | map(select(. != "") | split("\t") | {name: .[0], size: (.[1] | tonumber)})'; }

diagnose() {
  local branch base wt pipelines git dispatcher scratch commands
  branch=$(jq -r '.fm.branch // ""' <<<"$parsed")
  base=$(jq -r '.fm.base_commit // ""' <<<"$parsed")
  wt=$(jq -r '.fm.worktree_path // ""' <<<"$parsed")
  pipelines=$(sp pipeline show | jq -R -s "$JQ_LIB parse_pipelines")
  git=$(git_state "$branch" "$base" "$wt")
  dispatcher=$(dispatcher_state)
  scratch=$(scratch_files | to_files)
  commands=$(command_files | to_files)
  jq --argjson pipelines "$pipelines" --argjson git "$git" --argjson dispatcher "$dispatcher" \
     --argjson scratch "$scratch" --argjson commands "$commands" \
     --arg spoolway_version "$(sp --version 2>/dev/null || echo unknown)" \
     "$JQ_LIB $JQ_DIAG" <<<"$parsed"
}

# The diagnosis salvage kept while the task stood on `blocked`, or `null`: none was kept, or the one
# there is of another run of the same task id.
first_diagnosis() {
  local run
  run=$(jq -r '.fm.run // ""' <<<"$parsed")
  if [ -f "$first_file" ] && jq -e --arg run "$run" '$run == "" or (.run // "") == $run' "$first_file" >/dev/null 2>&1; then
    cat -- "$first_file"
  else
    echo null
  fi
}

# ---------------------------------------------------------------------------------------------
# salvage
# ---------------------------------------------------------------------------------------------
salvage() {
  local rel=.scratch/spoolway/$task rows='' ok=true first=absent
  git -C "$main_checkout" check-ignore -q -- "$rel" \
    || die "$dest is not git-ignored in $main_checkout: add \`.scratch/\` to .gitignore or .git/info/exclude first" 3

  mkdir -p "$dest/scratch" "$dest/commands" "$dest/drafts"

  # The document as it stands, kept like any other copy: a road out strips or archives it.
  printf '%s\n' "$doc" >"$dest/.task.md.new"
  cmp -s -- "$dest/.task.md.new" "$dest/task.md" 2>/dev/null || cp --backup=numbered -- "$dest/.task.md.new" "$dest/task.md"
  rm -f -- "$dest/.task.md.new"

  # The first diagnosis: written once, while the task stands on `blocked`. A task that has moved on
  # is diagnosed as "not blocked", so a later salvage leaves the file alone; the record reads it.
  # One left by another run of the same id is kept as a numbered backup.
  if [ "$(first_diagnosis)" != null ]; then
    first=kept
  elif [ "$(jq -r '.fm.stage // ""' <<<"$parsed")" = blocked ]; then
    diagnose | jq --arg run "$(jq -r '.fm.run // ""' <<<"$parsed")" '. + {run: $run}' >"$dest/.first-diagnosis.new"
    cp --backup=numbered -- "$dest/.first-diagnosis.new" "$first_file"
    rm -f -- "$dest/.first-diagnosis.new"
    first=written
  fi

  copy_tree() {  # <kind> <source dir> <dest dir> <find args...>
    local kind=$1 from=$2 to=$3; shift 3
    local src name target size copied
    [ -d "$from" ] || return 0
    while IFS= read -r -d '' src; do
      name=${src#"$from"/}
      case $name in *$'\t'* | *$'\n'*) die "salvage stopped: \`$name\` has a tab or newline in its name" 1 ;; esac
      target=$to/$name
      size=$(stat -L -c %s -- "$src" 2>/dev/null || echo -1)
      copied=-1
      # A symlink is copied as the file it points at. A copy already there is left alone when it is
      # identical, and kept as a numbered backup when the source has changed since.
      if mkdir -p -- "$(dirname "$target")" \
         && { { [ -e "$target" ] && cmp -s -- "$src" "$target"; } || cp -pL --backup=numbered -- "$src" "$target" 2>/dev/null; }; then
        copied=$(stat -L -c %s -- "$target" 2>/dev/null || echo -1)
      fi
      if [ "$size" = -1 ] || [ "$size" != "$copied" ]; then ok=false; fi
      rows+=$(printf '%s\t%s\t%s\t%s\t%s' "$kind" "$src" "$target" "$size" "$copied")$'\n'
    done < <(find "$from" "$@" \( -type f -o -type l \) -print0 | LC_ALL=C sort -z)
  }
  copy_tree scratch "$home/scratch/$task" "$dest/scratch"
  copy_tree commands "$home/commands" "$dest/commands" -maxdepth 1 -name "$task · *"

  local files
  files=$(printf '%s' "$rows" | jq -R -s -c '
    split("\n") | map(select(. != "") | split("\t")
      | {kind: .[0], source: .[1], destination: .[2], size: (.[3] | tonumber), copied_size: (.[4] | tonumber),
         match: (.[3] == .[4] and .[3] != "-1")})')

  if [ "$ok" = false ]; then
    jq -n --arg task "$task" --arg dest "$dest" --argjson files "$files" \
      '{ok: false, task: $task, destination: $dest, files: $files, drafts: [], failed: [$files[] | select(.match | not) | .source]}'
    die "salvage stopped: a copy failed or differs in size; nothing was drafted" 1
  fi

  # One draft per note that asks a person to post or open something. Nothing is posted.
  local drafts='[]' note n step asks targets material path
  while IFS= read -r note; do
    [ -n "$note" ] || continue
    n=$(jq -r .n <<<"$note"); step=$(jq -r .step <<<"$note")
    path=$dest/drafts/$(printf '%02d' "$n")-$(tr -c 'a-z0-9\n-' '-' <<<"$step").md
    material=$(jq -r --argjson note "$note" --arg scratch "$home/scratch/$task/" --arg commands "$home/commands/" '
      def esc: gsub("(?<c>[.\\[\\](){}*+?|^$\\\\])"; "\\\(.c)");
      .[] | . as $f
      | ($f.source | ltrimstr($scratch) | ltrimstr($commands)) as $rel
      | select($note.text | contains($f.source) or test("(^|[\\s/`(\"\u0027])" + ($rel | esc) + "($|[^A-Za-z0-9_-])"))
      | .destination' <<<"$files")
    jq -r --argjson note "$note" --arg material "$material" '
      "DRAFT — nothing here has been posted or opened.\n\n"
      + "Source: handoff note \($note.n) (`\($note.step)`)\n"
      + "Asks a person to: \($note.asks | join(" and "))\n"
      + "Targets named: \(([$note.text | scan("#[0-9]+")] | unique | join(" ")) // "")\n"
      + "Salvaged material the note names:\n"
      + (if $material == "" then "- (none)\n" else ($material | split("\n") | map("- " + .) | join("\n")) + "\n" end)
      + "\nThe note, verbatim:\n\n"
      + ($note.text | split("\n") | map("> " + .) | join("\n")) + "\n"' <<<"$files" >"$path"
    drafts=$(jq -c --argjson note "$note" --arg path "$path" '. + [{note: $note.n, step: $note.step, asks: $note.asks, path: $path}]' <<<"$drafts")
  done < <(jq -c '.notes[] | select(.to_person and (.asks | length > 0))' <<<"$parsed")

  jq -n --arg task "$task" --arg dest "$dest" --argjson files "$files" --argjson drafts "$drafts" \
        --arg first "$first" --arg first_file "$first_file" \
    '{ok: true, task: $task, destination: $dest, document: ($dest + "/task.md"), first_diagnosis: {path: $first_file, state: $first},
      empty: ($files | length == 0), files: $files, drafts: $drafts}'
}


# ---------------------------------------------------------------------------------------------
# The two roads: choose, advance, retreat, record
# ---------------------------------------------------------------------------------------------
# Is every scratch file and command log copied as it stands now, and the document kept?
salvage_state() {
  local missing='' name
  [ -f "$dest/task.md" ] || missing+=task.md$'\n'
  while IFS=$'\t' read -r name _; do
    [ -z "$name" ] || cmp -s -- "$home/scratch/$task/$name" "$dest/scratch/$name" || missing+=scratch/$name$'\n'
  done < <(scratch_files)
  while IFS=$'\t' read -r name _; do
    [ -z "$name" ] || cmp -s -- "$home/commands/$name" "$dest/commands/$name" || missing+=commands/$name$'\n'
  done < <(command_files)
  printf '%s' "$missing" | jq -R -s -c --arg dest "$dest" \
    '(split("\n") | map(select(. != ""))) as $m | {destination: $dest, complete: ($m | length == 0), missing: $m}'
}

# Does the binary's own help still offer the flag? <flag> <subcommand words...>
help_has() {
  local flag=$1; shift
  sp "$@" --help </dev/null 2>/dev/null | grep -qE -- "(^|[[:space:],])$flag([[:space:],=]|\$)"
}

read -r -d '' JQ_ROADS <<'JQ' || true
# The diagnosis in, the roads out. A judgment is a step whose failure routes back to a working step
# instead of to `blocked`; the resume step is the first judgment downstream of the implementer.
def roads($p; $pipelines; $salvage):
  . as $d
  | $p.fm as $fm
  | ($fm.arrivals // {} | with_entries(.value |= tonumber)) as $arr
  # Each loop is the diagnosis's: the one a refusal line states, where it differs from the one in force.
  | (reduce $d.loops[] as $l ($pipelines[$fm.pipeline] // {}; .[$l.step].loop = $l.loop)) as $steps
  | ($fm.implementer // "implement") as $impl
  | def spent($s): $steps[$s].loop != null and (($arr[$s] // 0) >= $steps[$s].loop);
    def judgment($s):
      $s != null and $s != "blocked" and $steps[$s] != null
      and ($steps[$s].fail // "blocked") != "blocked" and $steps[$steps[$s].fail] != null;
    def first_judgment($s; $n):
      if $n > 30 or $s == null or $steps[$s] == null then null
      elif (passes_at_once($fm; $s) | not) and judgment($s) then $s
      else first_judgment($steps[$s].pass; $n + 1) end;
    def chain($s; $acc):
      if $s == null or $steps[$s] == null or any($acc[]; . == $s) then $acc else chain($steps[$s].pass; $acc + [$s]) end;
    # Where a failure lands: refused at a spent loop (the task parks), or on a step that starts a lane.
    def parks($s; $n):
      if $n > 30 or $s == null or $steps[$s] == null then true
      elif spent($s) then true
      elif passes_at_once($fm; $s) then parks($steps[$s].pass; $n + 1)
      else false end;
    [$p.log[] | capture("^- \\S+ \\S+ → `(?<s>[^`]+)`")? | .s] as $seq
  | ([range(0; $seq | length) | select($seq[.] == $impl)] | last // -1) as $visited
  # The implementer worked on a visit it left by its pass route; a visit that ended on `blocked` answered nothing.
  | ([range(0; $seq | length) | select($seq[.] == $impl and $seq[. + 1] == $steps[$impl].pass)] | last // -1) as $worked
  # A judgment has passed when the task left it by its pass route and the implementer has not been
  # visited since. It has failed when it left by another route and the implementer has not worked since.
  | def status($j):
      ([range(0; $seq | length) | select($seq[.] == $j)] | last) as $i
      | if $i == null then "not-run"
        elif $seq[$i + 1] == $steps[$j].pass then (if $i < $visited then "not-run" else "passed" end)
        elif $i < $worked then "not-run" else "failed" end;
    first_judgment($steps[$impl].pass; 0) as $resume
  | chain($resume; []) as $chain
  | [$chain[] | select(judgment(.))
     | {step: ., status: status(.), pass: $steps[.].pass, fail: $steps[.].fail, failure_parks: parks($steps[.].fail; 0)}] as $judgments
  # Open findings: one per failed judgment that is a command step, which leaves a log and no note,
  # then the `Finding <n>` notes a failed judgment left after the implementer's last note.
  | ([$p.notes[] | select(.step == $impl) | .n] | last // 0) as $after
  | [$judgments[] | select(.status == "failed" and $steps[.step].kind == "command") | .step as $s
     | ([$p.log[] | capture("^- \\S+ \\S+ `(?<s>[^`]+)` exited (?<code>[0-9]+) — see (?<log>.+)$")? | select(.s == $s)] | last) as $x
     | ($x.log // ([$d.commands[].name | select(. == "\($d.task) · \($s).log")][0] | if . == null then null else "\($home)/commands/\(.)" end)) as $log
     | {finding: $s, kind: "command-step", note: null, step: $s, for_person: false, criteria: [],
        exit: ($x.code // null | if . == null then null else tonumber end), log: $log,
        text: "exited \($x.code // "non-zero") — see \($log // "no log found")"}] as $failed_commands
  | (if any($judgments[]; .status == "failed") then
       $failed_commands + [$p.notes[] | select(.n > $after) | . as $note | select(any($judgments[]; .step == $note.step))
        | ($note.text | capture("^Finding (?<f>[0-9]+)")? // null) as $m | select($m != null)
        | {finding: ($m.f | tonumber), note: $note.n, step: $note.step, for_person: $note.to_person,
           criteria: ([$note.text | match("acceptance criterion ([0-9]+)"; "gi") | .captures[0].string | tonumber] | unique),
           text: $note.text}]
     else [] end) as $open
  | [$d.criteria[] | select(.passable | not)] as $unpassable
  | [$open[] | select(.for_person) | select(all(.criteria[]; . as $c | all($unpassable[]; .n != $c)))] as $stuck
  | ($d.spec.bound and $d.spec.keep_open_marker != "present") as $marker_missing
  | {d: $d, fm: $fm, arrivals: $arr, steps: $steps, implementer: $impl, resume_step: $resume, chain: $chain,
     judgments: $judgments, open: $open, unpassable: $unpassable, salvage: $salvage, marker_missing: $marker_missing,
     bound_issue: ($fm.ticket // $fm.source // null),
     recommendation: (
       if $d.stage != "blocked" then
         {road: null, conditions: [], reason: "the task is on `\($d.stage)`, not on `blocked`: it is not doomed"}
       elif ($d.git.worktree.present | not) then
         {road: "retreat", conditions: [], reason: "the task's worktree is gone: there is nowhere to repair"}
       elif $resume == null then
         {road: "retreat", conditions: [], reason: "no judgment sits downstream of `\($impl)`: a repair could not be judged again"}
       elif ($stuck | length) > 0 then
         {road: "retreat", conditions: [],
          reason: "finding \([$stuck[].finding | tostring] | join(", ")) is for a person and rests on no criterion that could be amended: the worktree cannot repair it"}
       else
         {road: "advance",
          conditions: ([$unpassable[] | {amend_criterion: .n, text, reason}]
                       + (if $marker_missing then [{restore_keep_open_marker: true}] else [] end)),
          reason: ("\([$open[] | select(.for_person | not)] | length) of \($open | length) open findings can be repaired in the worktree"
                   + (if ($unpassable | length) > 0 then ", and criterion \([$unpassable[].n | tostring] | join(", ")) can pass only if the person amends it"
                      else ", and every criterion can pass" end))}
       end)};

def brief: {finding, note, step, for_person, criteria} + (if .kind == "command-step" then {kind, exit, log} else {} end);
def draft_head($for): "DRAFT — nothing here has been posted.\n\nFor: \($for // "the bound issue")\n\n";
def cut($n): (split("\n")[0]) | if length > $n then .[0:$n] + "…" else . end;
# A draft's list, which says so when it has nothing to list.
def listed: if length == 0 then "- nothing\n" else join("") end;
# A command as one line a person can read and a shell can run.
def shown: map(if test("^[A-Za-z0-9_./:=@-]+$") then . else @sh end) | join(" ");

roads($p; $pipelines; $salvage) as $r
| $r.d as $d
| if $mode == "choose" then
    {task: $d.task, stage: $d.stage,
     recommendation: ($r.recommendation + {otherwise: (if $r.recommendation.road == "advance" then "retreat" else null end)}),
     resume_step: $r.resume_step,
     findings: {open: [$r.open[] | brief], repairable: [$r.open[] | select(.for_person | not) | .finding],
                for_person: [$r.open[] | select(.for_person) | .finding]},
     criteria_unpassable: [$r.unpassable[].n],
     judgments: $r.judgments, spec: $d.spec, salvage: $r.salvage, ruled_by: "the person"}

  elif $mode == "advance" then
    (if $step == "" then $r.resume_step else $step end) as $x
    | ([$r.chain | to_entries[] | select(.value == $x) | .key] | first) as $pos
    | (if $pos == null then [] else [$r.chain[0:$pos][] as $s | $r.judgments[] | select(.step == $s)] end) as $skipped
    | [$skipped[] | select(.status != "passed") | .step] as $unpassed
    | (if $x == $r.resume_step then "recommended" elif $x == $r.implementer then "extra-lap"
       elif $pos == null then "off-route" elif ($unpassed | length) > 0 then "one-way-door" else "skips-judgment" end) as $kind
    | ($r.arrivals[$r.implementer] // 0) as $laps
    | [ (if $d.stage != "blocked" then "not-blocked" else empty end),
        (if $x == null then "no-judgment-downstream" else empty end),
        (if $kind == "off-route" and $x != null then "off-route" else empty end),
        (if $r.marker_missing then "keep-open-marker-missing" else empty end),
        (if $kind == "one-way-door" and ($r.salvage.complete | not) then "salvage-incomplete" else empty end),
        (if $kind == "one-way-door" and $confirmed == "" then "not-confirmed" else empty end),
        (if $flags == "true" then empty else "resume-flags-not-in-help" end) ] as $refused
    | (if $message != "" then $message
       elif $kind == "extra-lap" then "spoolway-repair: one more implementer lap at \($x), arrival \($laps + 1) against loop \($r.steps[$x].loop), chosen by the person"
       elif $kind == "one-way-door" then "spoolway-repair: one-way door, resumed at \($x) past \($unpassed | join(", ")) not passed, \($r.open | length) findings open; salvage complete; the person said: \($confirmed)"
       elif $kind == "skips-judgment" then "spoolway-repair: resumed at \($x), past \([$skipped[].step] | join(", ")), by the person's choice"
       else "spoolway-repair: repaired by hand in the worktree; resumed at \($x) so every judgment runs again" end) as $said
    # The commits the branch gained since the first diagnosis go into the status log with the resume,
    # where the record finds them after the branch is squashed or gone.
    | ($said + (if $message == "" and ($repair.commits | length) > 0
                then "; repair commits: " + ([$repair.commits[] | split(" ")[0]] | join(", ")) else "" end)) as $msg
    | ($kind == "one-way-door" and ($refused | length) == 0) as $door_open
    | [$r.judgments[] | select(.step as $s | $pos == null or ($r.chain[$pos:] | any(. == $s)))
       | {step, fail_to: .fail, parks: .failure_parks, starts_a_lane: (.failure_parks | not)}] as $on_failure
    | {task: $d.task, step: $x, known_step: ($x == null or $r.steps[$x] != null), kind: $kind,
       resume_step: $r.resume_step, refused: $refused,
       command: (if ($refused | length) == 0 then ["spoolway", "resume", $d.task, "--stage", $x, "--message", $msg] else null end),
       shown: (if ($refused | length) == 0 then ["spoolway", "resume", $d.task, "--stage", $x, "--message", $msg] | shown else null end),
       message: $msg,
       warnings: ((if $kind == "one-way-door" then ["one-way-door"] elif $kind == "skips-judgment" then ["skips-judgment"] else [] end)
                  + (if any($on_failure[]; .parks) then ["a-judgment-failing-again-parks-the-task"] else [] end)),
       door: {crossed: ($kind == "one-way-door"), past: $unpassed, salvage_complete: $r.salvage.complete,
              confirmed: ($confirmed != ""), open: $door_open},
       skipped_judgments: $skipped,
       on_failure: $on_failure,
       extra_lap: {step: $r.implementer, loop: $r.steps[$r.implementer].loop, arrivals: $laps, arrival_would_be: ($laps + 1),
                   named: ($kind == "extra-lap")},
       keep_open_marker: $d.spec.keep_open_marker,
       repair: $repair,
       findings_open: [$r.open[] | brief],
       drafts: (if $door_open then [{kind: "pull-request", path: ($dest + "/drafts/pull-request-repair.md"), findings: ($r.open | length), body: pr_section($r; "door")}] else [] end)}

  elif $mode == "retreat" then
    [ (if $d.stage != "blocked" then "not-blocked" else empty end),
      (if $d.dispatcher.running then "dispatcher-running" else empty end),
      (if $r.salvage.complete then empty else "salvage-incomplete" end),
      (if ($d.git.branch // "") == "" then "no-branch" else empty end),
      (if $flags == "true" then empty else "unqueue-help-not-0-19" end) ] as $refused
    | ($dest + "/drafts/retreat-built-and-left.md") as $draft
    # The judgment that last left by its fail route, read from the log: what is left when no numbered
    # finding says it.
    | [$p.log[] | capture("^- \\S+ \\S+ → `(?<s>[^`]+)`")? | .s] as $seq
    | ([range(0; ($seq | length) - 1) | . as $i | $r.judgments[] | select(.step == $seq[$i] and .fail == $seq[$i + 1])
        | {step, fail_to: .fail}] | last // null) as $failed
    | (if $failed == null then null else
         $failed + {log_line: ([$p.log[] | select(test("^- \\S+ \\S+ `" + $failed.step + "` exited "))] | last // null)} end) as $failed
    # What the unqueue does (spoolway 0.19.0, observed.md): a started task has its worktree and its
    # local branch deleted whatever they hold, with no commit first. Loose work is therefore committed
    # and pushed here, and the remote is checked to hold the tip, before the unqueue is printed.
    | ($d.git.worktree.changes // [] | length) as $loose
    | ("chore(\($d.task)): keep the work of a retreated task") as $keep
    | {task: $d.task, road: "retreat", refused: $refused, dispatcher: $d.dispatcher,
       left: {findings: [$r.open[].finding], criteria: [$r.unpassable[].n], judgment: $failed},
       steps: (if ($refused | length) > 0 then [] else [
         {do: "comment", on: $r.bound_issue, draft: $draft},
         (if $loose > 0 then
            {do: "commit", files: $loose,
             command: ["bash", "-c", "git -C \"$1\" add -A && git -C \"$1\" commit -m \"$2\"", "retreat-commit", $d.git.worktree.path, $keep]}
          else empty end),
         {do: "push", command: ["git", "-C", $main, "push", "origin", $d.git.branch]},
         {do: "check-remote", command: ["bash", $script, "pushed", $d.task]},
         {do: "unqueue", command: ["spoolway", "queue", "unqueue", $d.task]},
         {do: "verify", command: ["bash", $script, "pushed", $d.task]},
         {do: "unlabel", on: $r.bound_issue, by: "hand"}] | map(if .command then . + {shown: (.command | shown)} else . end) end),
       expect: {observed_with: "spoolway 0.19.0", running: $d.spoolway,
                worktree: {path: $d.git.worktree.path, removed: true},
                uncommitted: {files: $loose, committed_by_the_retreat: ($loose > 0), commit: (if $loose > 0 then $keep else null end)},
                branch: {name: $d.git.branch, local: "deleted by the unqueue", remote: "holds the tip, checked before the unqueue", remote_sha: $d.git.remote.sha},
                scratch: {files: ($d.scratch | length), deleted: true},
                commands: {files: ($d.commands | length), deleted: false},
                document: {to: ($home + "/pending/" + $d.task + ".md"), keeps_arrivals: $r.arrivals,
                           a_requeue_keeps_them: false, a_requeue_reuses_the_branch: true},
                tracker: {comment: false, in_progress_label: "stays"},
                unverified: []},
       drafts: (if ($refused | length) > 0 then [] else [{kind: "retreat-comment", path: $draft, body: (
         draft_head($r.bound_issue)
         + "Task `\($d.task)` is retreated: its run is undone and its document goes back to the pending directory.\n\n"
         + "Cause: \($d.cause.sentence)\n\n"
         + "Built, on branch `\($d.git.branch)` (\($d.git.commits_since_base | length) commits since its base):\n"
         + ([$d.git.commits_since_base[] | "- \(.)\n"] | listed)
         + (if $loose > 0 then
              "
Not committed when the run stopped (\($loose) file(s)); the retreat commits them (`\($keep)`) and pushes them before the unqueue, which would delete them:
"
              + ([$d.git.worktree.changes[] | "- `\(.)`
"] | join(""))
            else "" end)
         + "\nLeft:\n"
         + ([$r.open[] | "- \(finding_label): \(.text | cut(200))\n"]
            + (if ($r.open | length) == 0 and $failed != null then
                 ["- `\($failed.step)` failed and sent the task back to `\($failed.fail_to)`, with no numbered finding\(if $failed.log_line then ": " + ($failed.log_line | ltrimstr("- ")) else "" end)\n"]
               else [] end)
            + [$r.unpassable[] | "- Criterion \(.n) cannot pass: \(.reason)\n"] | listed)
         + "\nSalvage: \($dest)\n")}] end)}

  else  # record
    # The cause is the one diagnosed while the task stood on `blocked`: the first diagnosis salvage
    # kept, or this one when the task still stands there. A task that has moved on has no other.
    ($first // (if $d.stage == "blocked" then $d else null end)) as $known
    | [ (if $r.salvage.complete then empty else "salvage-incomplete" end),
        (if $known == null then "no-first-diagnosis" else empty end) ] as $refused
    | ($known // $d) as $f
    # What the task document shows of the road since: the first arrival after the block's evidence
    # line (the resume), the commits that line names, and the stage reached.
    | ([range(0; $p.log | length) | select($p.log[.] == ($f.cause.evidence // ""))] | last) as $at
    | (if $at == null then null else
         [$p.log[($at + 1):][] | . as $ln | (capture("^- \\S+ \\S+ → `(?<step>[^`]+)`")? // empty)
          | select(.step != "blocked") | {step, line: ($ln | ltrimstr("- "))}] | first // null end) as $resume
    | [($resume.line // "") | capture("repair commits: (?<c>[0-9a-f]{7,40}(, [0-9a-f]{7,40})*)")? | .c | split(", ")[]] as $named
    | (if $road == "retreat" then null
       elif ($named | length) > 0 then {commits: $named, read_from: "resume-line"}
       elif $repair.readable then {commits: $repair.commits, read_from: "branch"}
       else {commits: [], read_from: null} end) as $made
    | {resume: $resume, stage: (if $source == "spoolway" then ($p.fm.stage // null) else null end)} as $outcome
    | ([ ($r.unpassable[] | {kind: "task-document", slug: "task-document-criterion-\(.n)",
                              what: "acceptance criterion \(.n) of task `\($d.task)` can never pass: \(.reason)",
                              evidence: "criterion \(.n): \(.text)"}),
         (if $f.plain_resume != null and $f.plain_resume.outcome == "bounces" then
            {kind: "pipeline", slug: "pipeline-plain-resume-bounces",
             what: "a plain resume of a task blocked from `\($f.plain_resume.step)` crosses \($f.plain_resume.passes_at_once | map("`\(.)`") | join(", ")), which passes at once, into `\($f.plain_resume.refused_at)`, whose loop is spent, and bounces back to `blocked`",
             evidence: ($f.last_refusal // "")}
          else empty end) ]) as $defects
    | {task: $d.task, road: $road, refused: $refused, document_source: $source, bound_issue: $r.bound_issue,
       cause: {kind: $f.cause.kind, evidence: $f.cause.evidence, source: (if $first != null then "first-diagnosis" else "this-diagnosis" end)},
       repair: $made, outcome: $outcome,
       salvage: $r.salvage.destination, defects: [$defects[] | {kind, what}],
       drafts: (if ($refused | length) > 0 then [] else
         [{kind: "issue-comment", on: $r.bound_issue, path: ($dest + "/drafts/record-comment.md"), body: (
            draft_head($r.bound_issue)
            + "Repair of task `\($d.task)` (spoolway-repair)\n\n"
            + "- Cause, as diagnosed while the task stood on `blocked`: \($f.cause.sentence)\n"
            + "- Evidence: \($f.cause.evidence // "none logged" | ltrimstr("- "))\n"
            + "- Road: " + (if $road == "advance" then "advance; repaired in the task's worktree and resumed at `\($resume.step // $r.resume_step)`"
                            elif $road == "door" then "the one-way door; resumed past a judgment that had not passed, with \($r.open | length) findings open, listed in the pull request"
                            else "retreat; the run was undone, the document is back in the pending directory and the branch is on the remote" end) + "\n"
            + (if $made == null then "" else
                 "- Repair commits: " + (if ($made.commits | length) > 0 then ($made.commits | join(", "))
                                         elif $made.read_from == "branch" then "nothing: the branch has no commit since the diagnosis"
                                         else "not readable: the resume line names none, and the branch is gone or rewritten" end) + "\n"
                 + "- Resumed: \($resume.line // "nothing: the task document shows no arrival after the block")\n"
                 + "- Reached: " + (if $outcome.stage != null then "`\($outcome.stage)`"
                                    else "not shown: spoolway no longer holds the document, and the salvaged copy is older" end) + "\n"
               end)
            + "- Salvage: \($dest) (\($kept.scratch) scratch files, \($kept.commands) command-step logs, the task document as it stood)\n"
            + "- Branch: `\($d.git.branch)`; " + (if $d.git.local_branch_exists then "commits the remote lacks: \($d.git.remote.commits_not_on_remote // "unknown")"
                                                   elif $d.git.remote.branch == "present" then "deleted locally by the unqueue; the remote holds it at \($d.git.remote.sha[0:7])"
                                                   else "neither local nor on the remote" end) + "\n"
            )}]
         + (if $road == "retreat" then [] else
             [{kind: "pull-request", path: ($dest + "/drafts/pull-request-repair.md"),
               findings: (if $road == "door" then ($r.open | length) else 0 end), body: pr_section($r | .d.cause = $f.cause; $road)}] end)
         + [$defects[] | {kind: "finding", defect: .kind, path: ($dest + "/drafts/finding-" + .slug + ".md"), body: (
             "DRAFT — nothing here has been posted.\n\nFor: the findings channel, one comment per run on the project's weekly digest issue\n\n"
             + "- Finding: \(.what)\n"
             + "- Class: bug or enhancement, for the person to rule\n"
             + "- Evidence: \(.evidence | ltrimstr("- "))\n"
             + "- Where seen: task `\($d.task)`, \($r.bound_issue // "no bound issue")\n"
             + "- Suggests: the type that owns the \(.kind), for the person to rule\n")}]
       end)}
  end
JQ

# The pull request's repair section. It is defined ahead of the program that uses it.
read -r -d '' JQ_PR <<'JQ' || true
def finding_label:
  if .kind == "command-step" then "Failed command step `\(.step)`"
  else "Finding \(.finding) (`\(.step)`\(if .for_person then ", for a person" else "" end))" end;
def pr_section($r; $road):
  "DRAFT — nothing here has been posted.\n\nFor: the task's pull request, once it exists\n\n"
  + "## Came out of a repair\n\n"
  + "Task `\($r.d.task)` was doomed and was repaired with spoolway-repair. The cause, as diagnosed then: \($r.d.cause.sentence)\n\n"
  + (if $road == "door" then
       "It left by the one-way door: it was resumed past "
       + ([$r.judgments[] | select(.status != "passed") | "`\(.step)`"] | join(", "))
       + ", which had not passed. These findings were open and have not been judged since:\n\n"
       + ([$r.open[] | "- [ ] \(finding_label): \(.text | split("\n")[0] | if length > 240 then .[0:240] + "…" else . end)\n"] | join(""))
     else
       "The repair was made by hand in the task's worktree and judged again from `\($r.resume_step)`.\n"
     end);
JQ

roads() {  # <mode> <flags found in help: true|false>
  local diag pipelines kept first tip branch repair='{"readable": false, "commits": []}'
  diag=$(diagnose)
  first=$(first_diagnosis)
  # The commits the branch gained since the first diagnosis, while both ends can still be read.
  tip=$(jq -r --argjson p "$parsed" '(.git.commits_since_base[0] // "" | split(" ")[0]) as $t | if $t != "" then $t else ($p.fm.base_commit // "") end' <<<"$first" 2>/dev/null || true)
  branch=$(jq -r '.git.branch // ""' <<<"$first" 2>/dev/null || true)
  if [ -n "$tip" ] && [ -n "$branch" ] && git -C "$main_checkout" merge-base --is-ancestor "$tip" "refs/heads/$branch" 2>/dev/null; then
    repair=$(git -C "$main_checkout" log --format='%h %s' "$tip..refs/heads/$branch" | jq -R -s -c '{readable: true, commits: (split("\n") | map(select(. != "")))}')
  fi
  pipelines=$(sp pipeline show | jq -R -s "$JQ_LIB parse_pipelines")
  kept=$(jq -n --argjson s "$(find "$dest/scratch" -type f 2>/dev/null | wc -l)" --argjson c "$(find "$dest/commands" -type f 2>/dev/null | wc -l)" '{scratch: $s, commands: $c}')
  jq --argjson p "$parsed" --argjson pipelines "$pipelines" --argjson salvage "$(salvage_state)" --argjson kept "$kept" \
     --arg mode "$1" --arg flags "$2" --arg step "$step" --arg confirmed "$confirmed" --arg road "$road" \
     --arg message "${REPAIR_MESSAGE:-}" --arg source "$document_source" \
     --argjson first "$first" --argjson repair "$repair" \
     --arg dest "$dest" --arg home "$home" --arg main "$main_checkout" --arg script "$0" \
     "$JQ_LIB $JQ_PR $JQ_ROADS" <<<"$diag"
}

# Writes each {path, body} of `.drafts`, prints the object with the bodies dropped, and exits 1 on a
# refusal. Drafts exist only when nothing was refused, so a refusal writes nothing.
finish() {
  local out=$1 n i
  n=$(jq '.drafts | length' <<<"$out")
  [ "$n" = 0 ] || mkdir -p "$dest/drafts"
  for ((i = 0; i < n; i++)); do
    jq -r --argjson i "$i" '.drafts[$i].body' <<<"$out" >"$(jq -r --argjson i "$i" '.drafts[$i].path' <<<"$out")"
  done
  jq '.drafts |= map(del(.body))' <<<"$out"
  jq -e '.refused | length == 0' <<<"$out" >/dev/null || exit 1
}

choose() { roads choose true; }

advance() {
  local flags=true out
  help_has --stage resume && help_has --message resume || flags=false
  out=$(roads advance "$flags")
  [ "$(jq -r .known_step <<<"$out")" = true ] || die "\`$step\` is not a step of this task's pipeline (\`spoolway pipeline show\`)" 2
  finish "$(jq 'del(.known_step)' <<<"$out")"
}

retreat() {
  local flags=true
  # 0.19.0's `queue unqueue` has no `--force`; a binary whose help offers one is not the one observed.
  ! help_has --force queue unqueue || flags=false
  finish "$(roads retreat "$flags")"
}

record() { finish "$(roads record true)"; }

pushed() {
  local branch base wt git tip='' out
  branch=$(jq -r '.fm.branch // ""' <<<"$parsed")
  base=$(jq -r '.fm.base_commit // ""' <<<"$parsed")
  wt=$(jq -r '.fm.worktree_path // ""' <<<"$parsed")
  [ -n "$branch" ] || die "the document of \`$task\` names no branch" 2
  git=$(git_state "$branch" "$base" "$wt")
  # A local branch the unqueue deleted is pushed when the remote stands at, or past, the tip the first
  # diagnosis saw: the unqueue deletes only a branch the remote holds in full.
  tip=$(jq -r --arg base "$base" '(.git.commits_since_base[0] // "" | split(" ")[0]) as $t | if $t != "" then $t else $base end' <<<"$(first_diagnosis)" 2>/dev/null || true)
  # The retreat commits loose work before the push, so the remote may stand ahead of the tip the first
  # diagnosis saw: it holds the branch when that tip is an ancestor of it.
  local rsha descends=false
  rsha=$(jq -r '.remote.sha // ""' <<<"$git")
  if [ -n "$tip" ] && [ -n "$rsha" ] && git -C "$main_checkout" merge-base --is-ancestor "$tip" "$rsha" 2>/dev/null; then descends=true; fi
  out=$(jq --argjson descends "$descends" --arg task "$task" --arg source "$document_source" --arg pending "$pending/$task.md" --arg tip "$tip" \
     --argjson in_pending "$([ -f "$pending/$task.md" ] && echo true || echo false)" "$JQ_LIB"'
    ((.worktree.changes // []) | length == 0) as $clean
    | (.local_branch_exists and .remote.branch == "present" and .remote.commits_not_on_remote == 0) as $both
    | ((.local_branch_exists | not) and .remote.branch == "present" and $tip != "" and $descends) as $remote_only
    | {ok: ($clean and ($both or $remote_only)),
       task: $task, branch, local_branch_exists, remote, worktree,
       local_branch: (if .local_branch_exists then "kept" elif $remote_only then "deleted; the remote holds the tip of the first diagnosis" else "missing" end),
       pending_document: {path: $pending, present: $in_pending}, document_source: $source}' <<<"$git")
  printf '%s\n' "$out"
  jq -e .ok <<<"$out" >/dev/null
}

"$command"
