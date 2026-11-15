#!/usr/bin/env bash
# Written once by /spoolway-companion:setup from the companion's template, then yours: the
# companion never updates it; a later bump prints the template's changes for you to apply.
#
# The `extra-handover` step of the Developing pipeline, after `review` and before `handover`: for
# each extra repository the task's `repos` names, it squashes the worktree's branch to one commit
# titled with the task's `title:`, pushes it and opens its pull request, which names the task's
# issue by URL only and merges before this repository's. Then it waits for the checks of every
# one of those pull requests together, within one CI_WAIT_SECONDS, so the step's `timeout` holds
# whatever their number. A branch that changes nothing opens no pull request. A task that changed
# only extra repositories gets one comment on its issue naming them, since no merge here reaches
# it. With EXTRA_REPOS empty the step passes at once, and a task whose `repos` names another
# repository blocks. Exit 0 passes the step, anything else blocks the task.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

no_arguments extra-handover "$@"
own_step extra-handover

if step_skipped "${SPOOLWAY_TASK_FILE:-}" extra-handover; then
  echo "extra-handover: named in skip_steps, passing at once"
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
  echo "extra-handover: the task names no extra repository, passing at once"
  exit 0
fi

# The title is each extra pull request's title and its one commit's subject.
if ! title=$(frontmatter_value "$SPOOLWAY_TASK_FILE" title); then
  echo "extra-handover: the task title cannot be read (above). Nothing was pushed. Stop the dispatcher, fix \`title:\` in the task file or unqueue and requeue it, then resume" >&2
  exit 1
fi
if ! why=$(conventional_title "$title"); then
  echo "extra-handover: the task title \"$title\" is $why. Nothing was pushed. Stop the dispatcher, fix \`title:\` in the task file or unqueue and requeue it, then resume" >&2
  exit 1
fi
if lines=$(closing_keywords "$SPOOLWAY_TASK_FILE"); then
  echo "extra-handover: the task body has a closing keyword before an issue. Nothing was pushed. Rewrite these lines (\`part of #N\`, \`leaves #N open\`) in the task file with the dispatcher stopped, then resume:" >&2
  printf '%s\n' "$lines" >&2
  exit 1
fi
# A pull request in another repository names the task's issue by its full URL.
source=$(frontmatter_value "$SPOOLWAY_TASK_FILE" source)
[ -n "$source" ] || source=$(frontmatter_value "$SPOOLWAY_TASK_FILE" ticket)
case "$source" in
  "" | https://*/issues/*) ;;
  *)
    echo "extra-handover: the task names its issue as \"$source\", and a pull request in another repository needs its full URL. Nothing was pushed. Fix \`source:\` or \`ticket:\` in the task file with the dispatcher stopped, then resume" >&2
    exit 1
    ;;
esac

for tool in gh jq; do
  if ! command -v "$tool" > /dev/null; then
    echo "ENVIRONMENT: $tool is not on PATH; the extra pull requests cannot be opened or read" >&2
    exit 1
  fi
done

branch=$(git -C "$root" rev-parse --abbrev-ref HEAD)
task_base_branch=$(task_base "$SPOOLWAY_TASK_FILE")
extra_only=
if task_unchanged "$root" "$SPOOLWAY_TASK_FILE"; then extra_only=1; fi

# Every worktree is checked before anything is pushed.
for name in $names; do
  path=$(extra_worktree "$name" "$branch")
  if ! on_branch "$path" "$branch"; then
    echo "ENVIRONMENT: the task names $name and $path is not a worktree on $branch" >&2
    exit 1
  fi
  if [ -n "$(git -C "$path" status --porcelain)" ]; then
    echo "extra-handover: $path has uncommitted changes, which the checks never saw. Nothing was pushed" >&2
    exit 1
  fi
done

body=$(mktemp)
trap 'rm -f "$body"' EXIT
urls=
for name in $names; do
  checkout=$(extra_checkout "$name")
  path=$(extra_worktree "$name" "$branch")
  base=$(extra_base "$checkout" "$task_base_branch")
  git -C "$path" fetch -q origin "$base"
  fork=$(git -C "$path" merge-base "origin/$base" HEAD)
  if git -C "$path" diff --quiet "$fork" HEAD; then
    echo "extra-handover: $name changes nothing against origin/$base; no pull request there"
    continue
  fi
  if [ "$(git -C "$path" rev-list --count "$fork..HEAD")" != 1 ] || [ "$(git -C "$path" log -1 --format=%B)" != "$title" ]; then
    squashed=$(git -C "$path" commit-tree "HEAD^{tree}" -p "$fork" -m "$title")
    git -C "$path" reset -q --soft "$squashed"
  fi
  git -C "$path" fetch -q origin "+refs/heads/$branch:refs/remotes/origin/$branch" 2> /dev/null || true
  git -C "$path" push -q --force-with-lease origin "HEAD:refs/heads/$branch"

  url=$(open_pull_request "$path" "$branch")
  if [ -z "$url" ]; then
    {
      [ -n "$source" ] && printf 'Part of %s\n\n' "$source"
      if [ -n "$extra_only" ]; then
        echo "The $name half of the task \`${SPOOLWAY_TASK:-$branch}\`, which changes no file of $own."
      else
        echo "The $name half of the task \`${SPOOLWAY_TASK:-$branch}\`. This pull request merges first; the $own pull request on the same branch name, \`$branch\`, merges after it."
      fi
    } > "$body"
    (cd "$path" && gh pr create --base "$base" --head "$branch" --title "$title" --body-file "$body" > /dev/null)
    url=$(open_pull_request "$path" "$branch")
    if [ -z "$url" ]; then
      echo "extra-handover: no pull request open on $branch in $name after \`gh pr create\`" >&2
      exit 1
    fi
  fi
  # What GitHub itself parsed has the last word.
  closing=$(cd "$path" && gh pr view "$url" --json closingIssuesReferences --jq '[.closingIssuesReferences[].number | "#\(.)"] | join(" ")')
  if [ -n "$closing" ]; then
    echo "extra-handover: $url would close $closing on merge; edit its body to remove the closing keyword, then resume" >&2
    exit 1
  fi
  echo "extra-handover: $url is open on $branch"
  urls="$urls$url"$'\n'
done

if [ -z "$urls" ]; then
  echo "extra-handover: no extra repository changes anything; no extra pull request"
  exit 0
fi

# A task that changed only extra repositories: nothing merged here reaches its issue.
if [ -n "$extra_only" ] && [ -n "$source" ]; then
  comments=$(gh issue view "$source" --json comments --jq '.comments[].body')
  first=${urls%%$'\n'*}
  if [ "${comments#*"$first"}" != "$comments" ]; then
    echo "extra-handover: the input issue already links $first"
  else
    gh issue comment "$source" --body "This task changes only other repositories, and opens no pull request in $own. Its pull requests: $(printf '%s' "$urls" | tr '\n' ' ')A merge there does not reach this issue, so a person takes it from here by hand."
    echo "extra-handover: extra repositories only; commented on $source"
  fi
fi

wait_seconds=${CI_WAIT_SECONDS:-2100}
poll_seconds=${CI_POLL_SECONDS:-30}
case "$wait_seconds$poll_seconds" in
  *[!0-9]* | "") echo "extra-handover: CI_WAIT_SECONDS and CI_POLL_SECONDS must be whole numbers of seconds" >&2; exit 64 ;;
esac
start=$SECONDS
while true; do
  green=0 total=0 red= waiting=
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    total=$((total + 1))
    json=$(gh pr checks "$url" --json name,bucket,link 2> /dev/null || true)
    if ! printf '%s' "$json" | jq -e 'type == "array" and length > 0' > /dev/null 2>&1; then
      waiting="$waiting  $url reports no check yet"$'\n'
      continue
    fi
    detail=$(printf '%s' "$json" | jq -r '.[] | select(.bucket == "fail" or .bucket == "cancel") | "  \(.name) (\(.bucket)): \(.link)"')
    if [ -n "$detail" ]; then red="$red$url:"$'\n'"$detail"$'\n'; continue; fi
    detail=$(printf '%s' "$json" | jq -r '.[] | select(.bucket != "pass" and .bucket != "skipping") | "  \(.name) (\(.bucket)): \(.link)"')
    if [ -n "$detail" ]; then waiting="$waiting$url:"$'\n'"$detail"$'\n'; else green=$((green + 1)); fi
  done <<< "$urls"
  if [ -n "$red" ]; then
    echo "extra-handover: an extra pull request has failing checks:" >&2
    printf '%s' "$red" >&2
    exit 1
  fi
  if [ "$green" = "$total" ]; then
    echo "extra-handover: every check is green on the $total extra pull request(s)"
    exit 0
  fi
  if [ $((SECONDS - start)) -ge "$wait_seconds" ]; then
    echo "extra-handover: after ${wait_seconds}s these are not green (unfinished or with no check at all, not red); nothing to wait for is not a pass:" >&2
    printf '%s' "$waiting" >&2
    exit 1
  fi
  sleep "$poll_seconds"
done
