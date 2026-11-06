#!/usr/bin/env bash
# The `collect` step, last before `done` in the Developing and Materializing pipelines: at
# `done` spoolway deletes the task's scratch space and its command-step logs,
# so this step copies both out first. It is the net under the destination rule (what a person
# needs goes to the Handoff or the digest), not a replacement for it.
#
#   collect.sh --keep-days <n>
#
# It writes to the folder `spoolway-repair` salvages to, so a task salvaged by hand and one
# collected here look the same:
#
#   <main checkout>/.scratch/spoolway/<task>/
#     scratch/      every file of `<home>/scratch/<task>/`, subfolders kept
#     commands/     every `<home>/commands/<task> · *` file: the logs and what sits beside them
#     collect.tsv   what this run copied: kind, name, size at the source, size of the copy
#                   (a symlink row: the name reads `<name> -> <target>`, both sizes are the length of
#                   the link itself)
#
# `drafts/`, `task.md` and `first-diagnosis.json` there belong to the skill, as do their numbered
# backups (`task.md.~1~`): this step neither writes nor removes them.
# A copy already there is left alone when it is identical, and kept as a numbered backup when the
# source has changed since. A symlink is copied as a symlink (`cp -P`) with the target it has, to a
# file, to a directory or to nothing; it is never followed, so nothing outside the scratch space is read.
#
# The step's own log is still being written while it runs, so it is copied last and not compared.
# `skip_steps` is not read: every task that reaches `done` passes through here.
#
# Exit 0 passes the step, an empty or missing scratch space included. A destination that is not
# git-ignored, a copy that fails or one that differs in size exits 1: the step has no `on_fail`,
# so the task parks on `blocked`, before spoolway's cleanup, with nothing lost.
#
# After a good copy it removes the folders of other tasks in which nothing changed for
# `--keep-days` days. A folder whose `drafts/` holds a file, or whose task is still queued, is
# never removed. A sweep that fails is reported and does not fail the step.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

usage() { echo "usage: collect.sh --keep-days <n>" >&2; exit 64; }

keep_days=
while [ $# -gt 0 ]; do
  case $1 in
    --keep-days) [ $# -ge 2 ] || usage; keep_days=$2; shift 2 ;;
    *) usage ;;
  esac
done
[[ $keep_days =~ ^[1-9][0-9]*$ ]] || usage
own_step collect

task_file=${SPOOLWAY_TASK_FILE:-}
if [ -z "$task_file" ] || [ ! -f "$task_file" ]; then
  echo "collect: SPOOLWAY_TASK_FILE names no task file" >&2
  exit 64
fi
task=${SPOOLWAY_TASK:-$(frontmatter_value "$task_file" id)}
# A task id holds only lowercase letters, digits and hyphens (`spoolway task contract`, field `id`).
if [[ ! $task =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
  echo "collect: \`$task\` is not a task id" >&2
  exit 64
fi
step=${SPOOLWAY_STEP:-collect}

# A command step is handed no SPOOLWAY_SCRATCH: the project's home is the directory above the task
# file's (`queue/<id>.md`), and the main checkout is where this worktree's repository lives.
home=$(cd "$(dirname "$task_file")/.." && pwd)
main_checkout=$(dirname "$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)")
store=$main_checkout/.scratch/spoolway
dest=$store/$task

if ! git -C "$main_checkout" check-ignore -q -- ".scratch/spoolway/$task"; then
  echo "collect: $dest is not git-ignored in $main_checkout: add \`.scratch/\` to .gitignore or .git/info/exclude first" >&2
  exit 1
fi

mkdir -p "$dest/scratch" "$dest/commands"

rows=''
ok=true
# copy_tree <kind> <source dir> <dest dir> <find args...>
copy_tree() {
  local kind=$1 from=$2 to=$3; shift 3
  local src name target size copied link
  [ -d "$from" ] || return 0
  while IFS= read -r -d '' src; do
    name=${src#"$from"/}
    case $name in
      *$'\t'* | *$'\n'*) echo "collect: \`$name\` has a tab or newline in its name" >&2; ok=false; continue ;;
    esac
    target=$to/$name
    copied=-1
    if [ -L "$src" ]; then
      link=$(readlink -- "$src")
      case $link in
        *$'\t'* | *$'\n'*) echo "collect: the link \`$name\` has a tab or newline in its target" >&2; ok=false; continue ;;
      esac
      name="$name -> $link"
      size=$(stat -c %s -- "$src" 2> /dev/null || echo -1)
      if mkdir -p -- "$(dirname "$target")" \
        && { { [ -L "$target" ] && [ "$(readlink -- "$target")" = "$link" ]; } || cp -pP --backup=numbered -- "$src" "$target"; }; then
        copied=$(stat -c %s -- "$target" 2> /dev/null || echo -1)
      fi
    else
      size=$(stat -L -c %s -- "$src" 2> /dev/null || echo -1)
      if mkdir -p -- "$(dirname "$target")" \
        && { { [ -e "$target" ] && cmp -s -- "$src" "$target"; } || cp -p --backup=numbered -- "$src" "$target"; }; then
        copied=$(stat -L -c %s -- "$target" 2> /dev/null || echo -1)
      fi
    fi
    if [ "$size" = -1 ] || [ "$size" != "$copied" ]; then ok=false; fi
    rows+=$(printf '%s\t%s\t%s\t%s' "$kind" "$name" "$size" "$copied")$'\n'
  done < <(find "$from" "$@" \( -type f -o -type l \) -print0 | LC_ALL=C sort -z)
}
own_log="$task · $step.log"
copy_tree scratch "$home/scratch/$task" "$dest/scratch"
copy_tree commands "$home/commands" "$dest/commands" -maxdepth 1 -name "$task · *" ! -name "$own_log"

{ printf 'kind\tname\tsize\tcopied_size\n'; printf '%s' "$rows"; } > "$dest/collect.tsv"
echo "collect: $dest"
cat "$dest/collect.tsv"

if [ "$ok" = false ]; then
  echo "collect: a copy failed or differs in size (copied_size -1 is a failed copy); the scratch space and the logs are still in $home" >&2
  exit 1
fi
count=$(printf '%s' "$rows" | grep -c . || true)
echo "collect: $count files copied and equal in size"

# The sweep. Nothing above depends on it, and it never fails the step.
sweep() {
  local dir name
  for dir in "$store"/*/; do
    dir=${dir%/}
    [ -d "$dir" ] && [ ! -L "$dir" ] || continue
    name=$(basename "$dir")
    [ "$name" != "$task" ] || continue
    [ ! -e "$home/queue/$name.md" ] || continue
    [ -z "$(find "$dir/drafts" -type f -print -quit 2> /dev/null)" ] || { echo "collect: kept $dir, its drafts/ holds a file"; continue; }
    [ -z "$(find "$dir" -mtime "-$keep_days" -print -quit)" ] || continue
    rm -rf -- "$dir" && echo "collect: removed $dir, nothing changed in it for $keep_days days"
  done
}
sweep || echo "collect: the sweep of $store failed; nothing else is affected" >&2

# Last, so that the copy holds everything printed above. Still open, so not compared.
if [ -f "$home/commands/$own_log" ]; then
  cp -p -- "$home/commands/$own_log" "$dest/commands/$own_log" 2> /dev/null \
    || echo "collect: this step's own log could not be copied" >&2
fi
exit 0
