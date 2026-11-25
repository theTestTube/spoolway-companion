#!/usr/bin/env bash
# Shipped with the Materializing pipeline in this plugin's types, at the revision
# .spoolway/plugin.lock records: a retake rewrites it, so it carries no project's specifics. What
# differs between consumers is read from .spoolway/companion.env.
#
# The `backing` step of the Materializing pipeline: the backing gate. What the `recall` lane found
# in session history reaches the grill only when the project itself says it; a candidate that
# only a past session said is dropped. Same name in every consumer.
#
# A transcript is a pointer, never a source: without this gate a claim that only a past session
# made would enter a ticket as if the project had decided it. The lane writes one candidate per
# line into the task's scratch space, `recall.candidates.md`:
#
#   - <the claim, one sentence> | wiki: <page id> | ref: <#N | owner/repo#N | issue URL | path[:line]>
#
# and this step writes `recall.md` (admitted, what the grill reads) and `recall.dropped.md`
# (dropped, each with its reason) beside it. The backing rule this template ships:
#   - with `PAGES_DIR` set in `.spoolway/companion.env`, the `wiki:` field must name a page that
#     exists as `$PAGES_DIR/<page id>.md` in this worktree, and a path under `PAGES_DIR` is not a
#     reference: a page cannot back itself;
#   - without `PAGES_DIR`, this consumer keeps no pages: the `wiki:` field is not read, and the
#     reference alone backs the claim;
#   - either way `ref:` must name at least one issue the tracker answers for, or one file this
#     repository tracks. Several references may be given, separated by commas; one good one is
#     enough. A bare `#N` is an issue of `MATERIALIZING_REPO`, else of the run's own repository.
# Change the rule here if yours differs, and say so in this header.
#
# The step passes whatever it admits: no candidates, or none admitted, is a grill with no recall.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

no_arguments backing "$@"
own_step backing

task_file=${SPOOLWAY_TASK_FILE:-}
if [ -z "$task_file" ] || [ ! -f "$task_file" ]; then
  echo "backing: SPOOLWAY_TASK_FILE names no task file" >&2
  exit 64
fi
scratch=$(task_scratch "$task_file")
candidates=$scratch/recall.candidates.md
admitted=$scratch/recall.md
dropped=$scratch/recall.dropped.md

mkdir -p "$scratch"
rm -f "$admitted" "$dropped"

# `skip_steps: [recall]` leaves nothing to gate, and a candidates file left by hand is not read.
if step_skipped "$task_file" backing || step_skipped "$task_file" recall; then
  rm -f "$candidates"
  echo "backing: recall is named in skip_steps; the grill starts with no recalled candidates"
  exit 0
fi
if [ ! -s "$candidates" ]; then
  echo "backing: the recall step left no candidates; the grill starts with none"
  exit 0
fi

PAGES_DIR=$(companion_env PAGES_DIR)
PAGES_DIR=${PAGES_DIR#./}
PAGES_DIR=${PAGES_DIR%/}

# project_repo: the repository a bare `#N` names, resolved once and only when one is read.
PROJECT_REPO=
project_repo() {
  if [ -z "$PROJECT_REPO" ]; then
    PROJECT_REPO=$(companion_env MATERIALIZING_REPO)
    if [ -z "$PROJECT_REPO" ]; then
      PROJECT_REPO=$(cd "${SPOOLWAY_REPO:-$root}" && gh repo view --json nameWithOwner --jq .nameWithOwner 2> /dev/null) || PROJECT_REPO=
    fi
    if [ -z "$PROJECT_REPO" ]; then
      echo "ENVIRONMENT: backing: a candidate cites a bare #N, and MATERIALIZING_REPO is unset and gh cannot tell this run's repository" >&2
      exit 1
    fi
  fi
  echo "$PROJECT_REPO"
}

trim() { printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'; }

# page_id <field>: succeeds when the field names an existing page under PAGES_DIR; prints its id.
page_id() {
  local id
  id=$(trim "$1")
  id=${id#[[}; id=${id%]]}; id=${id%.md}
  printf '%s\n' "$id" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || return 1
  [ -f "$root/$PAGES_DIR/$id.md" ] || return 1
  echo "$id"
}

# backed_ref <reference>: succeeds for an issue the tracker answers for, or a file the worktree holds.
backed_ref() {
  local ref=$1 repo number path
  if [[ $ref =~ ^https://github\.com/([^/]+/[^/]+)/issues/([0-9]+)$ ]]; then
    repo=${BASH_REMATCH[1]}; number=${BASH_REMATCH[2]}
  elif [[ $ref =~ ^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#([0-9]+)$ ]]; then
    repo=${BASH_REMATCH[1]}; number=${BASH_REMATCH[2]}
  elif [[ $ref =~ ^#([0-9]+)$ ]]; then
    number=${BASH_REMATCH[1]}
    repo=$(project_repo) || exit 1
  else
    # Code: a file this repository tracks, with an optional `:line`. Tracked, so never a file a
    # lane has just written, never one outside the worktree, never through a symbolic link.
    path=${ref%%:*}
    case "$path" in '' | /* | '~'* | ./*) return 1 ;; esac
    if [ -n "$PAGES_DIR" ]; then
      case "$path" in "$PAGES_DIR"/*) return 1 ;; esac
    fi
    printf '%s\n' "$path" | grep -Eq '(^|/)\.\.(/|$)' && return 1
    [ -f "$root/$path" ] && [ ! -L "$root/$path" ] || return 1
    git -C "$root" ls-files --error-unmatch -- "$path" > /dev/null 2>&1
    return
  fi
  gh issue view "$number" -R "$repo" --json number --jq .number > /dev/null 2>&1
}

n_admitted=0
n_dropped=0
drop() {
  n_dropped=$((n_dropped + 1))
  printf -- '- %s\n  dropped: %s\n' "$1" "$2" >> "$dropped"
  echo "backing: dropped ($2): $1"
}

while IFS= read -r line || [ -n "$line" ]; do
  [[ $line =~ ^-[[:space:]] ]] || continue
  body=$(trim "${line#-}")
  if ! [[ $body =~ ^(.+)[[:space:]]\|[[:space:]]*wiki:(.*)[[:space:]]\|[[:space:]]*ref:(.*)$ ]]; then
    drop "$body" "not in the shape \`<claim> | wiki: <page> | ref: <issue or path>\`"
    continue
  fi
  claim=$(trim "${BASH_REMATCH[1]}")
  page_field=${BASH_REMATCH[2]}
  refs=${BASH_REMATCH[3]}
  page=
  if [ -n "$PAGES_DIR" ] && ! page=$(page_id "$page_field"); then
    drop "$body" "no page \`$(trim "$page_field")\` under $PAGES_DIR/"
    continue
  fi
  good=
  IFS=',' read -r -a list <<< "$refs"
  for ref in "${list[@]}"; do
    ref=$(trim "$ref")
    [ -n "$ref" ] || continue
    if backed_ref "$ref"; then good=${good:+$good, }$ref; fi
  done
  if [ -z "$good" ]; then
    drop "$body" "no issue the tracker answers for and no tracked file${PAGES_DIR:+ outside $PAGES_DIR/} among: $(trim "$refs")"
    continue
  fi
  n_admitted=$((n_admitted + 1))
  if [ -n "$page" ]; then
    printf -- '- %s (page `%s`; %s)\n' "$claim" "$page" "$good" >> "$admitted"
  else
    printf -- '- %s (%s)\n' "$claim" "$good" >> "$admitted"
  fi
done < "$candidates"

echo "backing: $n_admitted admitted, $n_dropped dropped"
