# Shared by the command steps of the companion's pipelines, and by the consumer's own scripts.
# Sourced, never run.

# companion_env <key> [<default>]: a consumer setting. The environment variable of that name wins;
# else the last `<key>=<value>` line of `.spoolway/companion.env` at the root of the checkout the
# caller runs in (COMPANION_ENV_FILE names another file). The file is read with grep, never
# sourced, so it runs nothing: a value is the text after the first `=`, with a trailing carriage
# return or blank and one pair of surrounding quotes taken off. Prints the default, or nothing,
# when neither sets the key; a step that needs the key is then a no-op.
companion_env() {
  local key=$1 default=${2:-} file value=
  case $key in '' | *[!A-Za-z0-9_]* | [0-9]*) echo "companion_env: \`$key\` is no key name" >&2; return 64 ;; esac
  if [ -n "${!key:-}" ]; then printf '%s\n' "${!key}"; return 0; fi
  file=${COMPANION_ENV_FILE:-$(git rev-parse --show-toplevel 2> /dev/null || pwd)/.spoolway/companion.env}
  if [ -f "$file" ]; then
    value=$(grep -E "^$key=" "$file" 2> /dev/null | tail -n 1 | cut -d= -f2-) || true
    value=${value%$'\r'}
    value="${value%"${value##*[![:space:]]}"}"
    case $value in \"*\" | \'*\') value=${value:1:${#value}-2} ;; esac
  fi
  printf '%s\n' "${value:-$default}"
}

# frontmatter_list <file> <key>: each item of the frontmatter list `key`, one per line, unquoted.
# Both YAML spellings are read:
#   skip_steps: [report, handover]
#   skip_steps:
#     - report
# No file, no key or an empty list prints nothing.
frontmatter_list() {
  local file=$1 key=$2
  [ -n "$file" ] && [ -f "$file" ] || return 0
  awk -v key="$key" '
    NR == 1 { if ($0 !~ /^---[ \t\r]*$/) exit; next }
    /^---[ \t\r]*$/ { exit }
    index($0, key ":") == 1 {
      inlist = 1
      v = substr($0, length(key) + 2); sub(/[ \t]+#.*$/, "", v)
      gsub(/[\[\]"\047\r]/, "", v)
      n = split(v, parts, /[ \t]*,[ \t]*/)
      for (i = 1; i <= n; i++) { gsub(/^[ \t]+|[ \t]+$/, "", parts[i]); if (parts[i] != "") print parts[i] }
      next
    }
    inlist && /^[ \t]*-[ \t]/ {
      v = $0; sub(/^[ \t]*-[ \t]*/, "", v); sub(/[ \t]+#.*$/, "", v)
      gsub(/["\047\r]/, "", v); gsub(/^[ \t]+|[ \t]+$/, "", v)
      if (v != "") print v
      next
    }
    { inlist = 0 }
  ' "$file"
}

# frontmatter_list_has <task-file> <key> <item>: succeeds when the task document's frontmatter
# list `key` holds the item. `grep` reads the whole list, so `pipefail` sees no broken pipe.
frontmatter_list_has() { [ -n "$3" ] && frontmatter_list "$1" "$2" | grep -xF -- "$3" > /dev/null; }

# step_skipped <task-file> <step>: succeeds when the task document's `skip_steps` names the step.
# `skip_steps` is a pass-through key of ours: spoolway keeps it verbatim, and only the queue
# screen's trial picker can write its own `skip:`.
step_skipped() { frontmatter_list_has "$1" skip_steps "$2"; }

# on_branch <dir> <branch>: succeeds when the directory is a git checkout on that branch.
on_branch() { [ "$(git -C "$1" rev-parse --abbrev-ref HEAD 2> /dev/null)" = "$2" ]; }

# open_pull_request <checkout> <branch>: the URL of the open pull request on the branch, or
# nothing. `gh` reads the repository from the directory it runs in, so a consumer's extra-*
# scripts can ask it of a worktree in another repository.
open_pull_request() {
  (cd "$1" && gh pr list --head "$2" --state open --json url --jq '.[0].url // empty')
}

# run_report_repo: the `owner/repo` a run report is filed in and read from. `RUN_REPORT_REPO` when
# set, in the environment or in `.spoolway/companion.env`, else the run's own repository, resolved at run time: `gh` reads it from the directory it runs
# in, `SPOOLWAY_REPO` when the run names one. No repository is named here. When it resolves to
# nothing it says so on stderr and fails, so a caller never files or reads under an empty name.
run_report_repo() {
  local repo
  repo=$(companion_env RUN_REPORT_REPO)
  if [ -n "$repo" ]; then echo "$repo"; return; fi
  repo=$(cd "${SPOOLWAY_REPO:-.}" && gh repo view --json nameWithOwner --jq .nameWithOwner) && [ -n "$repo" ] || {
    echo "run_report_repo: cannot tell which repository the run reports to: set RUN_REPORT_REPO or run inside a GitHub checkout gh can read" >&2
    return 1
  }
  echo "$repo"
}

# task_base <task-file>: the branch the task's pull requests open against, `develop` when unsaid.
task_base() {
  local base=
  [ -n "$1" ] && [ -f "$1" ] && base=$(frontmatter_value "$1" base)
  echo "${base:-develop}"
}

# task_starts_from <task-file>: the branch the task was cut from, the key spoolway writes into the
# task document when it cuts the worktree. 0.12.0 writes `starts_from`; the older `cut_from`
# spelling is still read, since 0.12.0 still accepts the alias but writes the new name.
task_starts_from() {
  local file=$1 from=
  [ -n "$file" ] && [ -f "$file" ] || return 0
  from=$(frontmatter_value "$file" starts_from) || return $?
  if [ -z "$from" ]; then from=$(frontmatter_value "$file" cut_from) || return $?; fi
  [ -n "$from" ] && echo "$from"
  return 0
}

# task_unchanged <root> <task-file>: succeeds when the task's worktree holds nothing to open a
# pull request for: nothing uncommitted and no difference from the branch the task was cut from.
# `spoolway stack` fails on exactly that, which is how a task that changed only its extra
# repositories reaches `handover`.
task_unchanged() {
  local root=$1 from= ref
  [ -n "$2" ] && [ -f "$2" ] && from=$(task_starts_from "$2")
  from=${from:-$(task_base "$2")}
  [ -z "$(git -C "$root" status --porcelain)" ] || return 1
  for ref in "refs/heads/$from" "refs/remotes/origin/$from"; do
    if git -C "$root" rev-parse -q --verify "$ref" > /dev/null; then
      git -C "$root" diff --quiet "$ref...HEAD"
      return
    fi
  done
  return 1
}

# frontmatter_value <file> <key>: one frontmatter value as a YAML reader gives it; nothing for a
# missing key. A plain value is read as written. A single-quoted one loses its quotes and each
# doubled apostrophe is one: spoolway writes a title with an apostrophe so. A double-quoted
# one has `\"`, `\\`, `\/` and `\t` undone; any other escape, an unclosed quote or text after the
# closing quote is refused on stderr, with nothing printed and a failing status.
frontmatter_value() {
  awk -v key="$2" -v file="$1" '
    function refuse(why) { printf "frontmatter_value: %s: `%s:` %s\n", file, key, why > "/dev/stderr"; exit 1 }
    NR == 1 { if ($0 !~ /^---[ \t\r]*$/) exit; next }
    /^---[ \t\r]*$/ { exit }
    index($0, key ":") == 1 {
      v = substr($0, length(key) + 2)
      sub(/^[ \t]+/, "", v); sub(/[ \t\r]+$/, "", v)
      q = substr(v, 1, 1)
      if (q != "\047" && q != "\"") { print v; exit }
      out = ""; n = length(v); closed = 0
      for (i = 2; i <= n; i++) {
        c = substr(v, i, 1)
        if (c == q) {
          if (q == "\047" && substr(v, i + 1, 1) == "\047") { out = out c; i++; continue }
          closed = 1; break
        }
        if (q == "\"" && c == "\\") {
          i++; e = substr(v, i, 1)
          if (e == "\"" || e == "\\" || e == "/") out = out e
          else if (e == "t") out = out "\t"
          else refuse("holds the escape \\" e ", which this reader does not undo: write the value single-quoted")
          continue
        }
        out = out c
      }
      if (!closed) refuse("opens a quote it never closes")
      if (substr(v, i + 1) !~ /^([ \t]+#.*)?$/) refuse("has text after its closing quote")
      print out
      exit
    }
  ' "$1"
}

# conventional_title <title>: succeeds for a Conventional Commits 1.0.0 line (a listed type, an optional scope, an optional `!`, a lowercase sentence, 128 characters at
# most) with no AI attribution wording; a title may still name `CLAUDE.md` or `.claude/`. On failure prints the reason and fails.
conventional_title() {
  local title=$1
  if [ "${#title}" -gt 128 ]; then echo "longer than 128 characters"; return 1; fi
  if ! printf '%s\n' "$title" | grep -Eq '^(feat|fix|docs|refactor|perf|test|build|ci|chore)(\([^()[:space:]]+\))?!?: [^[:space:][:upper:]]'; then
    echo "not \`type(scope): lowercase sentence\` with a type of feat, fix, docs, refactor, perf, test, build, ci or chore"
    return 1
  fi
  if printf '%s\n' "$title" | grep -Eiq 'co-authored|generated (with|by)|(written|made|authored|built) by (claude|an? ai)|🤖'; then
    echo "carries AI attribution"
    return 1
  fi
}

# strip_ai_trailer: stdin to stdout without trailing blank lines and without a last line that is
# a `Co-Authored-By:` trailer naming Claude, which is what `spoolway stack` appends.
strip_ai_trailer() {
  awk '
    { line[NR] = $0 }
    END {
      n = NR
      while (n > 0 && line[n] ~ /^[ \t\r]*$/) n--
      if (n > 0 && tolower(line[n]) ~ /^co-authored-by:.*claude/) n--
      while (n > 0 && line[n] ~ /^[ \t\r]*$/) n--
      for (i = 1; i <= n; i++) print line[i]
    }
  '
}

# closing_keywords <file>: prints each line of the task document's body that GitHub would read as
# a closing reference, and succeeds when there is one. GitHub's keywords are close, closes,
# closed, fix, fixes, fixed, resolve, resolves and resolved, with an optional colon, then an issue
# as `#N`, `owner/repo#N` or a URL. A negated sentence ("does not close #N") closes all the same,
# and the pull request body is the task body, so lane notes are scanned too.
closing_keywords() {
  awk '
    NR == 1 { if ($0 !~ /^---[ \t\r]*$/) body = 1; next }
    !body && /^---[ \t\r]*$/ { body = 1; next }
    body { print }
  ' "$1" | grep -Ei '(^|[^[:alnum:]_])(close[sd]?|fix(e[sd])?|resolve[sd]?):?[[:space:]]+(([[:alnum:]_.-]+/[[:alnum:]_.-]+)?#[0-9]+|https://github\.com/[^[:space:]]+/(issues|pull)/[0-9]+)'
}

# frontmatter_has_key <file> <key>: succeeds when the frontmatter sets the key, whatever its value.
frontmatter_has_key() {
  awk -v key="$2" '
    NR == 1 { if ($0 !~ /^---[ \t\r]*$/) exit 1; next }
    /^---[ \t\r]*$/ { exit !hit }
    index($0, key ":") == 1 { hit = 1 }
    END { exit !hit }
  ' "$1"
}

# lane_root [<dir>]: the worktree root of the lane that runs in <dir>, when it sits in a worktree
# named `<home>/worktrees/task-<id>`. Nothing when it does not: a command step runs in the main
# checkout, and a person's session in the project's own tree, and neither is a lane.
lane_root() {
  local dir=${1:-$PWD} root
  root=$(git -C "$dir" rev-parse --show-toplevel 2> /dev/null) || root=$dir
  case $root in */worktrees/task-*) printf '%s\n' "$root" ;; *) return 1 ;; esac
}

# lane_id [<dir>]: the task id the lane worktree in <dir> names, `task-<id>` without the prefix.
lane_id() {
  local root
  root=$(lane_root "${1:-$PWD}") || return 1
  printf '%s\n' "${root##*/task-}"
}

# lane_task_file [<dir>]: the task file of the lane worktree in <dir>, `queue/<id>.md` in its
# home, or `archive/<id>.md` once the task is archived. Nothing when neither exists.
lane_task_file() {
  local root home id file
  root=$(lane_root "${1:-$PWD}") || return 1
  home=$(dirname "$(dirname "$root")")
  id=${root##*/}; id=${id#task-}
  file=$home/queue/$id.md
  [ -f "$file" ] || file=$home/archive/$id.md
  [ -f "$file" ] || return 1
  printf '%s\n' "$file"
}

# lane_env [<dir>]: the lane's own environment, inferred from the worktree path when spoolway did
# not hand it over — a lane resumed after a dispatcher restart, a reboot or a usage-limit stop.
# <dir> defaults to the current directory. Prints `export` lines for SPOOLWAY_TASK,
# SPOOLWAY_TASK_FILE, SPOOLWAY_SCRATCH, SPOOLWAY_WORKTREE and SPOOLWAY_REPO, so a caller sets them
# with `eval "$(lane_env)"`. Prints nothing and fails when <dir> is not a lane worktree or the
# task file is missing. A value already set wins.
lane_env() {
  local root home id task_file repo
  root=$(lane_root "${1:-$PWD}") || return 1
  home=$(dirname "$(dirname "$root")")
  id=${root##*/}; id=${id#task-}
  task_file=$home/queue/$id.md
  [ -f "$task_file" ] || task_file=$home/archive/$id.md
  [ -f "$task_file" ] || return 1
  repo=$(sed -n 's/^root[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$home/project.toml" 2> /dev/null | tail -n 1)
  repo=${repo:-${SPOOLWAY_REPO:-}}
  printf 'export SPOOLWAY_TASK=%q\n' "${SPOOLWAY_TASK:-$id}"
  printf 'export SPOOLWAY_TASK_FILE=%q\n' "${SPOOLWAY_TASK_FILE:-$task_file}"
  printf 'export SPOOLWAY_SCRATCH=%q\n' "${SPOOLWAY_SCRATCH:-$home/scratch/$id}"
  printf 'export SPOOLWAY_WORKTREE=%q\n' "${SPOOLWAY_WORKTREE:-$root}"
  [ -n "$repo" ] && printf 'export SPOOLWAY_REPO=%q\n' "$repo"
  return 0
}

# lane_scratch [<dir>]: the task's scratch space, inferred from the worktree path in <dir>.
lane_scratch() {
  local root home id
  root=$(lane_root "${1:-$PWD}") || return 1
  home=$(dirname "$(dirname "$root")")
  id=${root##*/}; id=${id#task-}
  printf '%s\n' "$home/scratch/$id"
}

# require_scratch: the task's scratch space, or a loud failure. A caller that writes under
# `$SPOOLWAY_SCRATCH` runs this first: an empty value used to resolve to `/`.
require_scratch() {
  if [ -z "${SPOOLWAY_SCRATCH:-}" ]; then
    echo "require_scratch: SPOOLWAY_SCRATCH is empty; restore the lane environment with \`eval \"\$(scripts/spoolway/lane-env.sh)\"\` before writing to the scratch space" >&2
    return 1
  fi
  printf '%s\n' "$SPOOLWAY_SCRATCH"
}

# task_scratch <task-file>: the task's scratch space, `scratch/<id>` in the project's home, where
# the task file sits one level in (`queue/<id>.md`). A lane is handed the same directory as
# SPOOLWAY_SCRATCH and a command step is handed nothing, so a script a lane runs takes the lane's
# and a command step derives it from the task file. Fails loudly when neither names one, so a
# caller never writes under an empty path.
task_scratch() {
  local home id
  if [ -n "${SPOOLWAY_SCRATCH:-}" ]; then echo "$SPOOLWAY_SCRATCH"; return; fi
  if [ -z "${1:-}" ] || [ ! -f "$1" ]; then
    echo "task_scratch: no task file and SPOOLWAY_SCRATCH is empty" >&2
    return 1
  fi
  home=$(cd "$(dirname "$1")/.." && pwd)
  id=${SPOOLWAY_TASK:-$(frontmatter_value "$1" id)}
  if [ -z "$id" ]; then
    echo "task_scratch: the task file names no id and SPOOLWAY_TASK is empty" >&2
    return 1
  fi
  echo "$home/scratch/$id"
}

# issue_url <text>: succeeds when the text is the URL of one GitHub issue and nothing else.
issue_url() {
  printf '%s\n' "$1" | grep -Eq '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/issues/[0-9]+$'
}

# issue_repo <issue-url>: its `owner/repo`.
issue_repo() { printf '%s\n' "$1" | sed -E 's#^https://github\.com/([^/]+/[^/]+)/issues/[0-9]+$#\1#'; }

# branch_base <root> <task-file>: the commit the task's branch left its base at. Candidates
# are the `base_commit` spoolway writes into the task document when it cuts the worktree, while it
# is behind HEAD, and the merge base with the branch the task was cut from (`starts_from`, else
# `cut_from`, else `base`, else `develop`), by the same two refs as `task_unchanged`. The nearest to
# HEAD wins: a base merged into the branch since the cut moves it forward. Nothing and a failure
# when none resolves.
branch_base() {
  local root=$1 from= ref commit= candidate best= count fewest=
  local -a candidates=()
  [ -n "$2" ] && [ -f "$2" ] && commit=$(frontmatter_value "$2" base_commit)
  if [ -n "$commit" ] && git -C "$root" merge-base --is-ancestor "$commit" HEAD 2> /dev/null; then
    candidates+=("$(git -C "$root" rev-parse "$commit^{commit}")")
  fi
  [ -n "$2" ] && [ -f "$2" ] && from=$(task_starts_from "$2")
  from=${from:-$(task_base "$2")}
  for ref in "refs/heads/$from" "refs/remotes/origin/$from"; do
    if git -C "$root" rev-parse -q --verify "$ref" > /dev/null; then
      candidate=$(git -C "$root" merge-base "$ref" HEAD) && candidates+=("$candidate")
    fi
  done
  # The nearest one: a base merged into the branch since it was cut moves the base forward.
  for candidate in "${candidates[@]}"; do
    count=$(git -C "$root" rev-list --count "$candidate..HEAD")
    if [ -z "$fewest" ] || [ "$count" -lt "$fewest" ]; then fewest=$count best=$candidate; fi
  done
  [ -n "$best" ] && echo "$best"
}

# merge_conflicts <root> <ref>: tries to merge <ref> into the checkout's HEAD without touching the
# worktree. If it conflicts, sets `conflict_tree` to the tree git would write and `conflict_files`
# to the conflicted paths, and returns 0. Returns 1 when the merge is clean. Returns 2, with an
# ENVIRONMENT line, when git cannot run the merge at all.
merge_conflicts() {
  local root=$1 ref=$2 out rc
  conflict_tree= conflict_files=()
  out=$(git -C "$root" merge-tree --write-tree --name-only HEAD "$ref" 2> /dev/null) && rc=0 || rc=$?
  case $rc in
    0) return 1 ;;
    1) ;;
    *) echo "ENVIRONMENT: git merge-tree could not merge $ref into HEAD (exit $rc)" >&2; return 2 ;;
  esac
  conflict_tree=$(printf '%s\n' "$out" | head -n 1)
  mapfile -t conflict_files < <(printf '%s\n' "$out" | tail -n +2 | awk 'NF == 0 { exit } { print }')
  return 0
}

# conflict_hunks_are_pins: stdin is a file with git conflict markers; succeeds when each conflict
# hunk's two sides are equal once the `verified_commit:` and `verified:` lines are taken out, so the
# only lines the two sides disagree on are pin lines.
conflict_hunks_are_pins() {
  awk '
    function pin(line) { return line ~ /^verified_commit:/ || line ~ /^verified:/ }
    /^<<<<<<</ { ours = ""; theirs = ""; in_ours = 1; in_theirs = 0; next }
    in_ours && /^=======$/ { in_ours = 0; in_theirs = 1; next }
    in_theirs && /^>>>>>>>/ { if (ours != theirs) bad = 1; in_theirs = 0; next }
    in_ours { if (!pin($0)) ours = ours $0 "\n"; next }
    in_theirs { if (!pin($0)) theirs = theirs $0 "\n"; next }
    END { exit bad }
  '
}

# conflicts_only_pins <root> <tree> <ref> <path>...: succeeds when every conflicted path is a page
# (one `.md` directly under PAGES_DIR) that exists on both sides and every one of its conflict
# hunks differs only in the `verified_commit:` and `verified:` frontmatter lines. It is how a
# conflict is told apart from one a person has to resolve.
conflicts_only_pins() {
  local root=$1 tree=$2 ref=$3; shift 3
  local pages_dir rest path
  pages_dir=$(companion_env PAGES_DIR)
  pages_dir=${pages_dir#./}
  pages_dir=${pages_dir%/}
  [ -n "$pages_dir" ] || return 1
  [ $# -gt 0 ] || return 1
  for path in "$@"; do
    rest=${path#"$pages_dir"/}
    [ "$rest" != "$path" ] || return 1
    case $rest in */* | "") return 1 ;; *.md) ;; *) return 1 ;; esac
    git -C "$root" cat-file -e "HEAD:$path" 2> /dev/null || return 1
    git -C "$root" cat-file -e "$ref:$path" 2> /dev/null || return 1
    git -C "$root" show "$tree:$path" 2> /dev/null | conflict_hunks_are_pins || return 1
  done
  return 0
}

# no_arguments <step> [<argument>...]: for a command step's script that defines no argument
# Exits 64 on any: `--help` handed to one of these used to run the step.
no_arguments() {
  local step=$1
  shift
  [ $# -eq 0 ] && return 0
  echo "$step: this script takes no argument, and \`$1\` was given. Nothing was done" >&2
  exit 64
}

# own_step <step> [<mode>]: a command step's script runs inside its own step and nowhere else.
# Exits 64 unless the task document's `stage:` is the step. The stage is read from the
# file, never from SPOOLWAY_STEP: a lane is handed that variable too, with its own step in it.
# Called after the arguments are read and before anything is written. `mode` names a mode of the
# script that only one step may run, for the message.
own_step() {
  local step=$1 what=${2:+ $2} task_file=${SPOOLWAY_TASK_FILE:-} stage
  if [ -z "$task_file" ] || [ ! -f "$task_file" ]; then
    echo "$step: SPOOLWAY_TASK_FILE names no task file" >&2
    exit 64
  fi
  stage=$(frontmatter_value "$task_file" stage)
  [ "$stage" = "$step" ] && return 0
  echo "$step: \`$(basename "$0")$what\` is the \`$step\` step and the task is on \`${stage:-no stage}\`. Only the dispatcher runs a step's script, when the task reaches the step: nothing was done. A lane never runs it; a person brings a stopped task back with \`spoolway resume <task> --stage $step\`" >&2
  exit 64
}
