#!/usr/bin/env bash
# Shipped with the Materializing pipeline in this plugin's types, at the revision
# .spoolway/plugin.lock records: a retake rewrites it, so it carries no project's specifics. What
# differs between consumers is read from .spoolway/companion.env.
#
# The `drafts` step of the Materializing pipeline: every ticket the `tickets` lane opened gets one
# draft Developing task in the project's `pending/` directory, and nothing is queued. Same name in
# every consumer.
#
# The lane never writes into `pending/`. It leaves, in the task's scratch space,
#
#   tickets.md     one line per ticket it opened:
#                    - <issue URL> | draft: <task id>
#                    - <issue URL> | draft: none
#   drafts/<id>.md one Developing task document per `draft: <task id>` line
#
# and this step checks the set and copies it, all or nothing:
#   - `tickets.md` names at least one ticket, each once, and never the spec itself;
#   - a ticket in this project's repository has a draft. `draft: none` is only for a ticket of
#     another project, whose queue is not this one: a person drafts that task there. This
#     project's repository is `MATERIALIZING_REPO` in `.spoolway/companion.env`, else the run's
#     own repository as `gh` reads it;
#   - each draft is bound to its ticket by `ticket:` (the full URL), runs on `developing`, sets
#     `base:`, has a Conventional Commits title, carries no `close_on_merge` (that key is for a
#     spec, and a ticket closes when its pull request merges) and no closing keyword in its body;
#   - each draft carries a title and repositories the owner approved: its title is the title of
#     one ticket of the grill's `breakdown.md`, and no other draft carries it, and its `repos` is
#     that ticket's `- repos:` line, as a set. A draft with no `repos` changes this repository
#     alone, named as `OWN_REPO` below says;
#   - no draft is left without a ticket line;
#   - `spoolway task contract --from` accepts the set: ids, `depends_on`, shared `base`, the
#     group's `group_description`. It is the validation `queue add` runs, with nothing saved.
#
# Writing a document into `pending/` does not queue it: a person selects the group on the queue
# screen. This script never calls `spoolway queue` and never writes under `queue/`.
# On any problem nothing is written, every reason goes to `drafts.problems.md` in the scratch
# space, and the step fails back to `tickets`.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

no_arguments drafts "$@"
own_step drafts

PROJECT_REPO=$(companion_env MATERIALIZING_REPO)
if [ -z "$PROJECT_REPO" ]; then
  PROJECT_REPO=$(cd "${SPOOLWAY_REPO:-$root}" && gh repo view --json nameWithOwner --jq .nameWithOwner 2> /dev/null) || PROJECT_REPO=
fi
[ -n "$PROJECT_REPO" ] || { echo "ENVIRONMENT: drafts: MATERIALIZING_REPO is unset and gh cannot tell this run's repository" >&2; exit 1; }

# How this repository is named in a `repos` list, for a draft that carries none. The repository's
# own name by default (`acme/shop` is `shop`); set it to the entry your `repos` lists use.
OWN_REPO=${PROJECT_REPO##*/}
task_file=${SPOOLWAY_TASK_FILE:-}
if [ -z "$task_file" ] || [ ! -f "$task_file" ]; then
  echo "drafts: SPOOLWAY_TASK_FILE names no task file" >&2
  exit 64
fi
if step_skipped "$task_file" drafts || step_skipped "$task_file" tickets; then
  echo "drafts: tickets is named in skip_steps, passing at once"
  exit 0
fi

home=$(cd "$(dirname "$task_file")/.." && pwd)
scratch=$(task_scratch "$task_file")
tickets=$scratch/tickets.md
drafts=$scratch/drafts
pending=$home/pending
spec=$(frontmatter_value "$task_file" ticket)
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Every reason this step fails is also left in the scratch space, where the `tickets` lane reads
# it when the task comes back: a command step's output goes to a log, not to the task file.
reasons=$scratch/drafts.problems.md
breakdown=$scratch/breakdown.md
mkdir -p "$scratch"
rm -f "$reasons"
problems=0
problem() { echo "drafts: $1" >&2; echo "- $1" >> "$reasons"; problems=$((problems + 1)); }

if [ ! -s "$tickets" ]; then
  problem "the tickets step left no tickets.md, so there is no record of the tickets it opened. Nothing was written to pending/"
  exit 1
fi

# The grill writes each ticket of the breakdown as a heading `## <n>. <title>` followed by its
# `- project:`, `- repos:` and `- blocked by:` lines (its prompt sets the shape). Only those lines,
# up to the first other line, are read, so a list in the ticket's criteria is never taken for
# them. Each title maps to its repositories, sorted and joined by one space, so two spellings of
# one set compare equal.
repo_set() { tr ', \t' '\n\n\n' | sed '/^$/d' | LC_ALL=C sort -u | paste -sd' ' -; }
declare -A approved_repos=() repos_line=() title_draft=()
approved_titles=()
breakdown_problem=
if [ ! -f "$breakdown" ]; then
  breakdown_problem="there is no breakdown.md, so nothing says which title and repositories the owner approved; block"
else
  approved= in_meta= meta_line='^-[[:space:]]+[a-z][a-z ]*:'
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    if [[ $line =~ ^\#\#[[:space:]]+[0-9]+\.[[:space:]]+(.*[^[:space:]])[[:space:]]*$ ]]; then
      approved=${BASH_REMATCH[1]} in_meta=1
      if [ -n "${approved_repos[$approved]+set}" ]; then
        problem "breakdown.md: two tickets carry the title \"$approved\", so a draft cannot say which it is; block naming them"
      fi
      approved_titles+=("$approved")
      approved_repos[$approved]=
    elif [ -n "$in_meta" ] && [[ $line =~ ^-[[:space:]]+repos:[[:space:]]*(.*)$ ]]; then
      repos_line[$approved]=1
      approved_repos[$approved]=$(printf '%s' "${BASH_REMATCH[1]}" | tr -d '[]"`'"'" | repo_set)
    elif ! [[ $line =~ $meta_line ]]; then
      in_meta=
    fi
  done < "$breakdown"
  [ "${#approved_titles[@]}" -gt 0 ] ||
    breakdown_problem="breakdown.md has no ticket heading in the shape \`## <n>. <title>\`, so no title or repository was approved; block"
fi
# against_breakdown <draft id> <document>: the draft's title and `repos` are what the owner approved.
against_breakdown() {
  local id=$1 doc=$2 title repos
  if [ -n "$breakdown_problem" ]; then
    # Said once, whatever the number of drafts, and only when there is a draft to hold to it.
    [ "$breakdown_problem" = said ] || problem "$breakdown_problem"
    breakdown_problem=said
    return
  fi
  title=$(frontmatter_value "$doc" title)
  # An empty key would stop the script under `set -u`; the title check has named it already.
  [ -n "$title" ] || return 0
  if [ -z "${approved_repos[$title]+set}" ]; then
    problem "$id.md: the title \"$title\" is the title of no ticket of breakdown.md. Carry the approved title verbatim, or block naming the ticket; the approved titles: $(printf '"%s"; ' "${approved_titles[@]}")"
    return
  fi
  if [ -n "${title_draft[$title]:-}" ]; then
    problem "$id.md and ${title_draft[$title]}.md carry the title of one ticket of breakdown.md, \"$title\""
    return
  fi
  title_draft[$title]=$id
  if [ -z "${repos_line[$title]:-}" ]; then
    problem "breakdown.md: the ticket \"$title\" has no \`- repos:\` line under its heading, so its repositories were never approved; block naming the ticket"
    return
  fi
  if [ -z "${approved_repos[$title]}" ]; then
    problem "breakdown.md: the ticket \"$title\" has an empty \`- repos:\` line, so its repositories were never approved; block naming the ticket"
    return
  fi
  repos=$(frontmatter_list "$doc" repos | repo_set)
  repos=${repos:-$OWN_REPO}
  [ "$repos" = "${approved_repos[$title]}" ] || problem "$id.md: \`repos\` is $repos, and the breakdown approved ${approved_repos[$title]}. Carry the approved repositories, or block naming the ticket"
}

declare -A seen_ticket=() named_draft=()
count=0
while IFS= read -r line || [ -n "$line" ]; do
  [[ $line =~ ^-[[:space:]] ]] || continue
  if ! [[ $line =~ ^-[[:space:]]+([^[:space:]|]+)[[:space:]]*\|[[:space:]]*draft:[[:space:]]*([^[:space:]]+)[[:space:]]*$ ]]; then
    problem "tickets.md: not in the shape \`- <issue URL> | draft: <task id or none>\`: $line"
    continue
  fi
  url=${BASH_REMATCH[1]}; draft=${BASH_REMATCH[2]}
  count=$((count + 1))
  if ! issue_url "$url"; then problem "tickets.md: \"$url\" is not the full URL of an issue"; continue; fi
  if [ "$(lower "$url")" = "$(lower "$spec")" ]; then problem "tickets.md: $url is the spec itself, not a ticket"; continue; fi
  key=$(lower "$url")
  if [ -n "${seen_ticket[$key]:-}" ]; then problem "tickets.md: $url is listed twice"; continue; fi
  seen_ticket[$key]=1

  if [ "$draft" = none ]; then
    if [ "$(lower "$(issue_repo "$url")")" = "$(lower "$PROJECT_REPO")" ]; then
      problem "$url is a ticket of this project and has no draft task: \`draft: none\` is only for a ticket of another project"
    else
      echo "drafts: $url belongs to another project; a person drafts its task there"
    fi
    continue
  fi

  # The id names a file here and in pending/: letters, digits and hyphens, nothing a path could use.
  if ! [[ $draft =~ ^[a-z][a-z0-9-]*$ ]]; then problem "tickets.md: \"$draft\" is not a task id (lowercase letters, digits and hyphens, starting with a letter)"; continue; fi
  doc=$drafts/$draft.md
  if [ -n "${named_draft[$draft]:-}" ]; then problem "draft \`$draft\` is named by two tickets"; continue; fi
  named_draft[$draft]=1
  if [ ! -f "$doc" ]; then problem "$url names the draft \`$draft\`, and there is no $doc"; continue; fi
  [ "$(frontmatter_value "$doc" id)" = "$draft" ] || problem "$draft.md: \`id:\` is \"$(frontmatter_value "$doc" id)\", not the file's name"
  [ "$(lower "$(frontmatter_value "$doc" ticket)")" = "$(lower "$url")" ] || problem "$draft.md: \`ticket:\` is \"$(frontmatter_value "$doc" ticket)\", not $url"
  [ "$(frontmatter_value "$doc" pipeline)" = developing ] || problem "$draft.md: \`pipeline:\` is \"$(frontmatter_value "$doc" pipeline)\", not developing"
  [ -n "$(frontmatter_value "$doc" base)" ] || problem "$draft.md: sets no \`base:\`"
  if frontmatter_has_key "$doc" close_on_merge; then problem "$draft.md: carries \`close_on_merge\`, which is for a task bound to a spec; a ticket closes when its pull request merges"; fi
  if ! why=$(conventional_title "$(frontmatter_value "$doc" title)"); then problem "$draft.md: the title is $why"; fi
  against_breakdown "$draft" "$doc"
  if lines=$(closing_keywords "$doc"); then problem "$draft.md: the body has a closing keyword before an issue, which the handover step refuses: $(printf '%s' "$lines" | head -1)"; fi
done < "$tickets"

[ "$count" -gt 0 ] || problem "tickets.md lists no ticket"

if [ -d "$drafts" ]; then
  for doc in "$drafts"/*.md; do
    [ -e "$doc" ] || continue
    id=$(basename "$doc" .md)
    [ -n "${named_draft[$id]:-}" ] || problem "$id.md is a draft no line of tickets.md names"
  done
fi

if [ "$problems" -gt 0 ]; then
  echo "drafts: $problems problem(s); nothing was written to pending/. The issues already opened stay as they are: correct tickets.md and the drafts, and open no issue again" >&2
  exit 1
fi

if [ "${#named_draft[@]}" -eq 0 ]; then
  echo "drafts: every ticket belongs to another project; nothing to write to pending/"
  exit 0
fi

# spoolway's own validation of the set, the one `queue add --from` runs, with nothing saved.
if ! contract=$(spoolway -C "${SPOOLWAY_REPO:-.}" task contract --from "$drafts" 2>&1); then
  problem "spoolway refuses the set; nothing was written to pending/:"
  printf '%s\n' "$contract" | tee -a "$reasons" >&2
  exit 1
fi

# All or nothing: a document of the same name with other content is somebody's, and is kept.
for id in "${!named_draft[@]}"; do
  if { [ -e "$pending/$id.md" ] || [ -L "$pending/$id.md" ]; } && ! cmp -s "$drafts/$id.md" "$pending/$id.md"; then
    problem "$pending/$id.md exists with other content; nothing was written. Give the draft another id, in its file name, its \`id:\` and tickets.md"
    exit 1
  fi
done
# Staged beside pending/ first, so a copy that fails leaves pending/ as it was.
mkdir -p "$pending"
stage=$(mktemp -d "$home/pending.XXXXXX")
trap 'rm -rf "$stage"' EXIT
for id in "${!named_draft[@]}"; do cp "$drafts/$id.md" "$stage/$id.md"; done
for id in "${!named_draft[@]}"; do
  mv -f "$stage/$id.md" "$pending/$id.md"
  echo "drafts: wrote $pending/$id.md"
done
echo "drafts: ${#named_draft[@]} draft task(s) in pending/ for $count ticket(s); none is queued. A person sends them from the queue screen"
