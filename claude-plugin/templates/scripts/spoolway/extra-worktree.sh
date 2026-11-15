#!/usr/bin/env bash
# Written once by /spoolway-companion:setup from the companion's template, then yours: the
# companion never updates it; a later bump prints the template's changes for you to apply.
#
# The `extra-worktree` step of the Developing pipeline: it cuts a worktree on the task's branch
# name in each extra repository the task's `repos` names, from the task's `base` (or that
# repository's default branch when it has no such branch). A worktree already on the branch, as
# on a resume, passes. With EXTRA_REPOS empty this repository has no extra one: the step passes
# at once, and a task whose `repos` names another repository blocks, so no extra pull request is
# silently skipped. Exit 0 passes the step, anything else blocks the task.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

no_arguments extra-worktree "$@"
own_step extra-worktree

if step_skipped "${SPOOLWAY_TASK_FILE:-}" extra-worktree; then
  echo "extra-worktree: named in skip_steps, passing at once"
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
  echo "extra-worktree: the task names no extra repository, passing at once"
  exit 0
fi

branch=$(git -C "$root" rev-parse --abbrev-ref HEAD)
task_base_branch=$(task_base "${SPOOLWAY_TASK_FILE:-}")
for name in $names; do
  checkout=$(extra_checkout "$name")
  path=$(extra_worktree "$name" "$branch")
  if [ -e "$path" ]; then
    if on_branch "$path" "$branch"; then
      echo "extra-worktree: $path is already on $branch"
      continue
    fi
    echo "ENVIRONMENT: $path exists and is not a worktree on $branch; move it away, then resume" >&2
    exit 1
  fi
  base=$(extra_base "$checkout" "$task_base_branch")
  if [ -z "$base" ]; then
    echo "ENVIRONMENT: the origin of $checkout answers with neither $task_base_branch nor a default branch" >&2
    exit 1
  fi
  git -C "$checkout" fetch -q origin "$base"
  mkdir -p "$(dirname "$path")"
  git -C "$checkout" worktree add -q -B "$branch" "$path" "origin/$base"
  git -C "$path" branch -q --unset-upstream 2> /dev/null || true
  if ! on_branch "$path" "$branch"; then
    echo "ENVIRONMENT: \`git worktree add\` left no worktree on $branch at $path" >&2
    exit 1
  fi
  echo "extra-worktree: cut $path on $branch from origin/$base"
done
