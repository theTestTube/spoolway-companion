#!/usr/bin/env bash
# Written once by /spoolway-companion:setup from the companion's template, then yours: the
# companion never updates it; a later bump prints the template's changes for you to apply.
#
# The `extra-cleanup` step of the Developing pipeline, after `report` and before `collect`: it
# removes each extra worktree `extra-worktree` cut, and its local branch, once nothing in it would
# be lost. A worktree with uncommitted changes, files under `.scratch/`, the task's home or the
# collect folder inside it, or commits its origin lacks is left alone, and the step still passes:
# a person removes it by hand. With EXTRA_REPOS empty the step passes at once, and a task whose
# `repos` names another repository blocks. Exit 0 passes the step, anything else blocks the task.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

no_arguments extra-cleanup "$@"
own_step extra-cleanup

if step_skipped "${SPOOLWAY_TASK_FILE:-}" extra-cleanup; then
  echo "extra-cleanup: named in skip_steps, passing at once"
  exit 0
fi

# --- The extra repositories. The same block heads the three extra-* scripts. ---
# EXTRA_REPOS in .spoolway/companion.env names the extra repositories, `owner/name` or `name`,
# separated by blanks or commas; empty, the consumer has none and the step does what a mono-repo's
# does. Each one's checkout sits beside the main checkout under its own name, `../<name>`.
# EXTRA_WORKTREE_ROOT says where their worktrees are cut: `<root>/<name>/<branch, / as ->`. A
# leading `~` or `$HOME` is expanded, and a relative root is read from the main checkout, not from
# the task's worktree. A task's `repos` entry names a repository by `owner/name` or by `name`.
main_checkout=$(dirname "$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)")
extras=$(companion_env EXTRA_REPOS | tr ', \t' '\n\n\n' | sed '/^$/d' | sed 's#.*/##')
own=$(basename "$main_checkout")

# named: the extra repositories the task's `repos` names, one name per line. Any other entry is
# this repository, under whatever name the consumer gives it; a second such entry blocks the step,
# so a typo or a task meant for another project never silently skips a pull request.
named() {
  local entry name others=
  while IFS= read -r entry; do
    name=${entry##*/}
    if [ -n "$extras" ] && grep -qxF -- "$name" <<< "$extras"; then echo "$name"; continue; fi
    if [ -n "$others" ]; then
      echo "ENVIRONMENT: the task's \`repos\` names \`$others\` and \`$entry\`, and only one entry may be this repository: the extra ones are EXTRA_REPOS in .spoolway/companion.env (${extras:+$(tr '\n' ' ' <<< "$extras")}${extras:-empty}); fix \`repos\`, EXTRA_REPOS, or queue the task in its own project" >&2
      return 1
    fi
    others=$entry
  done < <(frontmatter_list "${SPOOLWAY_TASK_FILE:-}" repos)
}

# extra_checkout <name>: the checkout of an extra repository, resolved, or a failure.
extra_checkout() {
  if [ ! -d "$(dirname "$main_checkout")/$1/.git" ] && [ ! -f "$(dirname "$main_checkout")/$1/.git" ]; then
    echo "ENVIRONMENT: no checkout of $1 at $(dirname "$main_checkout")/$1, beside $main_checkout" >&2
    return 1
  fi
  (cd -P "$(dirname "$main_checkout")/$1" && pwd)
}

# extra_worktree <name> <branch>: where the extra repository's worktree for the branch is cut.
extra_worktree() {
  local top
  top=$(companion_env EXTRA_WORKTREE_ROOT)
  if [ -z "$top" ]; then
    echo "ENVIRONMENT: EXTRA_WORKTREE_ROOT is not set in .spoolway/companion.env, and EXTRA_REPOS names extra repositories" >&2
    return 1
  fi
  case $top in "~"*) top=$HOME${top#"~"} ;; '$HOME'*) top=$HOME${top#'$HOME'} ;; esac
  case $top in /*) ;; *) top=$main_checkout/$top ;; esac
  echo "${top%/}/$1/${2//\//-}"
}

# extra_base <checkout> <base>: the branch of the extra repository a task starts from: the task's
# `base` when its origin has it, else the origin's default branch.
extra_base() {
  if git -C "$1" ls-remote --exit-code -q origin "refs/heads/$2" > /dev/null 2>&1; then echo "$2"; return; fi
  git -C "$1" ls-remote --symref origin HEAD 2> /dev/null | sed -n 's#^ref: refs/heads/\(.*\)\tHEAD$#\1#p'
}
# --- End of the block. ---

names=$(named)
if [ -z "$names" ]; then
  echo "extra-cleanup: the task names no extra repository, passing at once"
  exit 0
fi

branch=$(git -C "$root" rev-parse --abbrev-ref HEAD)
task_base_branch=$(task_base "$SPOOLWAY_TASK_FILE")
# keep_reason <name> <worktree>: why the worktree is to be left alone, or nothing.
keep_reason() {
  local path=$2 real kept head remote base
  if [ -n "$(git -C "$path" status --porcelain)" ]; then echo "it has uncommitted changes"; return; fi
  if [ -n "$(find "$path/.scratch" -type f -print -quit 2> /dev/null)" ]; then
    echo "$path/.scratch holds files a removal would delete"; return
  fi
  real=$(cd -P "$path" && pwd)
  for kept in "$(cd -P "$(dirname "$SPOOLWAY_TASK_FILE")/.." && pwd)" "$main_checkout/.scratch/spoolway"; do
    case $kept/ in "$real"/*) echo "$kept is inside it, and the collect step still needs it"; return ;; esac
  done
  head=$(git -C "$path" rev-parse HEAD)
  remote=$(git -C "$path" ls-remote origin "refs/heads/$branch" 2> /dev/null) || remote=
  base=$(extra_base "$path" "$task_base_branch")
  if [ "$head" != "${remote%%[[:space:]]*}" ] && ! git -C "$path" diff --quiet "origin/$base...HEAD" 2> /dev/null; then
    echo "$branch has commits origin does not have"
  fi
}

for name in $names; do
  path=$(extra_worktree "$name" "$branch")
  if [ ! -e "$path" ]; then
    echo "extra-cleanup: no worktree at $path, nothing to remove"
    continue
  fi
  if ! on_branch "$path" "$branch"; then
    echo "extra-cleanup: $path is not a worktree on $branch; left alone"
    continue
  fi
  why=$(keep_reason "$name" "$path")
  if [ -n "$why" ]; then
    echo "extra-cleanup: $path left alone: $why"
    continue
  fi
  checkout=$(extra_checkout "$name")
  git -C "$checkout" worktree remove "$path"
  if [ -e "$path" ]; then
    echo "extra-cleanup: $path is still there after its removal" >&2
    exit 1
  fi
  if git -C "$checkout" rev-parse -q --verify "refs/heads/$branch" > /dev/null; then
    git -C "$checkout" branch -q -D "$branch"
  fi
  echo "extra-cleanup: removed $path and the local branch $branch of $name"
done
