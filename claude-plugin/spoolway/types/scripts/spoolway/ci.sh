#!/usr/bin/env bash
# The `ci` step of the Developing pipeline: waits for every check on the head commit of the task's
# pull request, and passes only when all of them are green and the pull request is mergeable. A
# person can run it by hand with SPOOLWAY_TASK_FILE naming a task document whose `stage:` is `ci`.
#
#   no open pull request on the branch   fails, saying so. It never passes on zero checks.
#   a check that failed or was cancelled fails at once, naming the check and its run URL.
#   a check not finished when the wait ends fails, naming it as unfinished and not as red.
#   no check reported at all when the wait ends fails, saying so.
#   a CONFLICTING pull request fails at once: GitHub runs no workflow on it, so its checks would
#   never change. The verdict reads `mergeable`/`mergeStateStatus` beside the checks, and the
#   block classifies the conflict with `git merge-tree`: when only the pages' `verified_commit:`/
#   `verified:` lines conflict it says to resume at `pin`, and names a person otherwise. A
#   `mergeable` of UNKNOWN (GitHub has not computed it yet) is not yet a pass; the step keeps
#   waiting, as it does for BEHIND, BLOCKED and DRAFT.
#   a pull request whose head is not the commit its worktree is on is not read: `pin` and the
#   unblocker push right before this step, and GitHub may still show the previous head with its
#   green checks. The wait covers it; at the limit the step fails naming both commits.
#
# Skipped checks count as green, as they do for GitHub's own merge gate. Pull requests in a
# consumer's extra repositories are its own extra-* scripts' to open and watch: a task that changed
# nothing in this repository opens no pull request here, and this step says so and passes.
#
# CI_WAIT_SECONDS (default 2100) is how long to wait for unfinished checks, CI_POLL_SECONDS
# (default 30) how often to look; set the step's `timeout:` above the first. No `on_fail`: a fail
# parks the task on `blocked` (a way back to `implement` would run `handover` again).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

no_arguments ci "$@"
own_step ci

if step_skipped "${SPOOLWAY_TASK_FILE:-}" ci; then
  echo "ci: named in skip_steps, passing at once"
  exit 0
fi

for tool in gh jq; do
  if ! command -v "$tool" > /dev/null; then
    echo "ENVIRONMENT: $tool is not on PATH; the pull request's checks cannot be read" >&2
    exit 1
  fi
done

wait_seconds=${CI_WAIT_SECONDS:-2100}
poll_seconds=${CI_POLL_SECONDS:-30}
case "$wait_seconds$poll_seconds" in
  *[!0-9]* | "") echo "ci: CI_WAIT_SECONDS and CI_POLL_SECONDS must be whole numbers of seconds" >&2; exit 64 ;;
esac

branch=$(git -C "$root" rev-parse --abbrev-ref HEAD)
base_branch=$(task_base "${SPOOLWAY_TASK_FILE:-}")
base_ref="origin/$base_branch"

# Targets: "<label>|<directory gh runs in>|<pull request url>", one per pull request to wait on.
targets=()

if [ -n "${SPOOLWAY_TASK_FILE:-}" ] && [ -f "$SPOOLWAY_TASK_FILE" ] && task_unchanged "$root" "$SPOOLWAY_TASK_FILE"; then
  echo "ci: nothing changed in this repository, so no pull request was opened here; passing at once"
  exit 0
fi

url=$(cd "$root" && gh pr list --head "$branch" --state open --json url --jq '.[0].url // empty')
if [ -z "$url" ]; then
  echo "ci: no open pull request on $branch: nothing to wait for, and a task never passes on zero checks. Open it (handover) or name ci in skip_steps, then resume" >&2
  exit 1
fi
targets+=("pull request|$root|$url")

# check_target <label> <dir> <url>: sets `state` to green, red, pending, none, conflicting or
# stale, and `detail` to the lines naming the checks behind it (stale: the two commits). The
# verdict reads `mergeable`/`mergeStateStatus` beside the checks: CONFLICTING is its own state,
# and an UNKNOWN mergeability is pending even when every check is green. stale means the pull
# request's head is not the commit <dir> is on, so its checks are not those of this work and are
# not read.
check_target() {
  local dir=$2 url=$3 info json head local_head mergeable merge_state
  local_head=$(git -C "$dir" rev-parse HEAD 2> /dev/null || true)
  info=$(cd "$dir" && gh pr view "$url" --json headRefOid,mergeable,mergeStateStatus 2> /dev/null || true)
  head=$(printf '%s' "$info" | jq -r '.headRefOid // empty' 2> /dev/null || true)
  mergeable=$(printf '%s' "$info" | jq -r '.mergeable // empty' 2> /dev/null || true)
  merge_state=$(printf '%s' "$info" | jq -r '.mergeStateStatus // empty' 2> /dev/null || true)
  if [ "$head" != "$local_head" ]; then
    state=stale detail="  pull request head ${head:-unknown}, worktree ${local_head:-unknown}"
    return
  fi
  if [ "$mergeable" = CONFLICTING ] || [ "$merge_state" = DIRTY ]; then
    state=conflicting detail=
    return
  fi
  json=$(cd "$dir" && gh pr checks "$url" --json name,bucket,link 2> /dev/null || true)
  if ! printf '%s' "$json" | jq -e 'type == "array" and length > 0' > /dev/null 2>&1; then
    state=none detail=
    return
  fi
  detail=$(printf '%s' "$json" | jq -r '.[] | select(.bucket == "fail" or .bucket == "cancel") | "  \(.name) (\(.bucket)): \(.link)"')
  if [ -n "$detail" ]; then state=red; return; fi
  detail=$(printf '%s' "$json" | jq -r '.[] | select(.bucket != "pass" and .bucket != "skipping") | "  \(.name) (\(.bucket)): \(.link)"')
  if [ -n "$detail" ]; then state=pending; return; fi
  if [ -z "$mergeable" ] || [ "$mergeable" = UNKNOWN ]; then
    state=pending detail="  mergeability is UNKNOWN; GitHub has not finished computing it"
    return
  fi
  state=green detail=
}

# conflict_message <dir>: the block message for a CONFLICTING pull request, classified with
# `git merge-tree` against `$base_ref`. Says to resume at `pin` when only the pages' pin lines
# conflict; names a person otherwise.
conflict_message() {
  local dir=$1 rc
  if ! git -C "$dir" rev-parse -q --verify "$base_ref" > /dev/null; then
    echo "ci: this branch conflicts with $base_branch, and no local $base_ref is here to classify it. Fetch it, or a person resolves the conflict" >&2
    return
  fi
  rc=0
  merge_conflicts "$dir" "$base_ref" || rc=$?
  case $rc in
    0)
      if conflicts_only_pins "$dir" "$conflict_tree" "$base_ref" "${conflict_files[@]}"; then
        echo "ci: merging $base_ref conflicts only in the pages' \`verified_commit:\`/\`verified:\` lines. Resume this task at \`pin\`: it merges $base_ref keeping this branch's pins, moves them to the merge commit, and re-checks" >&2
      else
        echo "ci: the conflict touches more than the pages' pin lines. A person resolves it, then resumes:" >&2
        printf '  %s\n' "${conflict_files[@]}" >&2
      fi
      ;;
    1) echo "ci: the local $base_ref does not conflict with this branch; the pull request is CONFLICTING for GitHub. Fetch $base_branch, or a person looks at the pull request" >&2 ;;
    *) ;;
  esac
}

start=$SECONDS
while true; do
  all_green=1 failed=
  for t in "${targets[@]}"; do
    IFS='|' read -r label dir url <<< "$t"
    check_target "$label" "$dir" "$url"
    case "$state" in
      red)
        echo "ci: the $label has failing checks, $url:" >&2
        printf '%s\n' "$detail" >&2
        failed=1 ;;
      conflicting)
        echo "ci: the $label is CONFLICTING, $url:" >&2
        conflict_message "$dir"
        failed=1 ;;
      green) ;;
      *) all_green=
         if [ $((SECONDS - start)) -ge "$wait_seconds" ]; then
           if [ "$state" = stale ]; then
             echo "ci: the $label head never became the worktree's commit after ${wait_seconds}s, $url. Push it, or wait for GitHub to catch up, then resume:" >&2
             printf '%s\n' "$detail" >&2
           elif [ "$state" = none ]; then
             echo "ci: the $label reports no check at all after ${wait_seconds}s, $url. Nothing to wait for is not a pass" >&2
           else
             echo "ci: the $label has checks not finished after ${wait_seconds}s (unfinished, not red), $url:" >&2
             [ -z "$detail" ] || printf '%s\n' "$detail" >&2
           fi
           failed=1
         fi ;;
    esac
  done
  [ -z "$failed" ] || exit 1
  if [ -n "$all_green" ]; then
    for t in "${targets[@]}"; do echo "ci: every check is green on ${t##*|}"; done
    exit 0
  fi
  sleep "$poll_seconds"
done
