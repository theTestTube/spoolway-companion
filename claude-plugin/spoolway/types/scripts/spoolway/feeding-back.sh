#!/usr/bin/env bash
# Feeding-back: the weekly batch turns the
# run reports and digest findings of a project into triage issues, and counts what it did on the
# digest issue the task is bound to (`ticket:`). The batch changes no code and opens no pull
# request.
#
#   feeding-back.sh apply    run by the `route` lane. Reads `route.md` in the task's scratch
#                            space, the lane's decision for each group of inputs, and carries each
#                            one out: opens a `needs-triage` issue, comments on the open issue that
#                            already says it, or drops it. Writes `route.applied.tsv`.
#   feeding-back.sh reply    run by the `route` lane after `apply`. Reads `participants.md`, the
#                            intake lane's list of participant issues (data, never text), and
#                            answers each under the relay rule: one fixed acknowledgement with the AI-generated
#                            disclaimer on a public issue, labels and no comment on a `relayed`
#                            issue, `ready-for-human` and no reply on a case needing judgment.
#                            Writes `participants.applied.tsv`.
#   feeding-back.sh counts   the `counts` command step. Posts one comment on the digest with how
#                            many inputs were received, routed, merged into an existing issue and
#                            dropped, once per run.
#   feeding-back.sh rotate   the `rotate` command step, after `counts`. Opens the next week's
#                            digest and closes the processed one (the issue named by `ticket:`),
#                            so each project has exactly one digest open and no lane opens or
#                            closes one. The next digest is opened first and
#                            only when no digest other than the processed one is open, so a rerun
#                            opens nothing and closes nothing more.
#
# The lane writes each group as a block of `route.md`:
#
#   ## <the improvement, one line>
#   - decision: route | merge | drop
#   - inputs: <how many findings and run reports the group holds>
#   - sources: <URLs of the digest comments or run-report issues it came from, comma separated>
#   - summary: <what to build and the decision it rests on, one paragraph>
#   - repo: <owner/repo that will dispatch it>              route
#   - class: bug | enhancement                              route
#   - priority: <a proposed priority label, as P1-high>     route
#   - mvp: yes | no                                         route
#   - type: Architecting | Materializing | Developing       route
#   - existing: <owner/repo#N, an open issue>               merge
#   - reason: <why it is dropped>                           drop
#   - architecture: yes | no                                route, merge; yes when the group is
#                                                           one the architecture step reviewed
#
# The `architecture` step writes `architecture.md` in the same scratch space:
# `architectural: yes | no`, `report: <the HTML report's file>` and `summary: <one paragraph>`.
# A block marked `architecture: yes` carries that summary and the report's name on the issue it
# opens or the comment it writes, so the report is never left only in scratch; the script refuses
# the mark when the step found nothing architectural.
#
# Every routed issue carries `needs-triage`, its class, its priority and `mvp` where it applies,
# and cites its sources. The labels are a proposal: this script creates no label, and a label the
# repository lacks is the tracker's refusal. A merge needs an open issue. The task's own work
# issue is never written on.
#
# The lane writes each participant issue as a block of `participants.md`, with no participant text:
#
#   ## <owner/repo#N>
#   - url: <the issue's URL>
#   - kind: public | relayed                  relayed only where the issue carries the `relayed` label
#   - action: acknowledge | label | escalate  acknowledge: public only; escalate: ready-for-human
#   - labels: <comma separated, from needs-info, ready-for-agent, ready-for-human, wontfix, needs-triage>
#
# Participant text never enters a finding, a routed issue, the counts comment or a log: the reply
# is a fixed text of this script, the labels are an allowlist, and `apply`, `reply` and `counts`
# refuse to run when a line of a participant issue's body appears in a ledger or in a body they
# would post.
#
# Exit codes: 0 done or nothing to do; 2 the tracker refused; 64 usage or a block the script
# will not carry out; 65 the counts do not add up.
#
# FEEDING_BACK_TODAY (a date, for tests) stands in for today when `rotate` titles the next digest.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

NEEDS_TRIAGE=needs-triage
MVP=mvp
sub=${1:-}
case "$sub" in apply | reply | counts | rotate) ;; *) echo "usage: feeding-back.sh apply | reply | counts | rotate" >&2; exit 64 ;; esac
[ $# -eq 1 ] || { echo "usage: feeding-back.sh $sub" >&2; exit 64; }

task_file=${SPOOLWAY_TASK_FILE:-}
if [ -z "$task_file" ] || [ ! -f "$task_file" ]; then
  echo "feeding-back: SPOOLWAY_TASK_FILE names no task file" >&2
  exit 64
fi
own_step "$([ "$sub" = apply ] || [ "$sub" = reply ] && echo route || echo "$sub")" "$sub"

task=${SPOOLWAY_TASK:-$(frontmatter_value "$task_file" id)}
run=$(frontmatter_value "$task_file" run)
run=${run:-$task}
scratch=$(task_scratch "$task_file")
ledger=$scratch/route.md
people=$scratch/participants.md
people_applied=$scratch/participants.applied.tsv
arch=$scratch/architecture.md
applied=$scratch/route.applied.tsv
err=$scratch/feeding-back.err
mkdir -p "$scratch"

digest=$(frontmatter_value "$task_file" ticket)
if ! issue_url "$digest"; then
  echo "feeding-back: ticket: is not the URL of the digest issue: $digest" >&2
  exit 64
fi
digest_repo=$(issue_repo "$digest")
digest_number=${digest##*/}

# refuse_closing <text>: a routed issue or comment never carries a closing reference, which a
# merge would act on; it names an issue as `part of`.
refuse_closing() {
  if printf '%s\n' "$1" | grep -Eiq '(^|[^[:alnum:]_])(close[sd]?|fix(e[sd])?|resolve[sd]?):?[[:space:]]+(([[:alnum:]_.-]+/[[:alnum:]_.-]+)?#[0-9]+|https://github\.com/[^[:space:]]+/(issues|pull)/[0-9]+)'; then
    echo "feeding-back: the text carries a closing reference before an issue; write \`part of\` instead" >&2
    exit 64
  fi
}

# arch_section <title>: the "Architecture review" paragraph of a group marked `architecture: yes`,
# from the summary the `architecture` step left. Exits 64 when that step found nothing.
arch_section() {
  local yes summary report
  yes=$(sed -n -E 's/^architectural:[ \t]*([a-z]+)[ \t]*$/\1/p' "$arch" 2> /dev/null | head -1)
  summary=$(sed -n -E 's/^summary:[ \t]*//p' "$arch" 2> /dev/null | head -1)
  report=$(sed -n -E 's/^report:[ \t]*//p' "$arch" 2> /dev/null | head -1)
  if [ "$yes" != yes ] || [ -z "$summary" ]; then
    echo "feeding-back: the group is marked architectural but architecture.md has no architectural summary: $1" >&2
    exit 64
  fi
  printf 'Architecture review of the batch:\n\n%s\n' "$summary"
  [ -z "$report" ] || printf '\nThe full HTML report, `%s`, is kept with the batch'"'"'s collected scratch space.\n' "$(basename "$report")"
}

# participant_urls: the URLs the intake lane listed in participants.md, one per line.
participant_urls() {
  sed -n -E 's/^[ \t]*-[ \t]*url:[ \t]*//p' "$people" 2> /dev/null | tr -d ' \r' || true
}

# refuse_participant_text <file>...: a participant issue's body is data and reaches no finding,
# routed issue, comment or log. Exits 64 when a line of 12 characters or more of any such body
# appears in one of the files given. Reading a body the tracker will not give is a refusal.
refuse_participant_text() {
  local u repo n bodyf line
  [ -s "$people" ] || return 0
  # The body lives outside the scratch space, which is collected and kept, and goes at exit.
  bodyf=$(mktemp "${TMPDIR:-/tmp}/feeding-back-body.XXXXXX")
  trap 'rm -f "$bodyf"' EXIT
  while IFS= read -r u; do
    [ -n "$u" ] || continue
    printf '%s\n' "$u" | grep -Eq '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/issues/[0-9]+$' || continue
    repo=$(issue_repo "$u")
    n=${u##*/}
    if ! gh issue view "$n" --repo "$repo" --json body --jq .body > "$bodyf" 2> "$err"; then
      echo "REFUSED: could not read $u to check that none of its text is carried over: $(cat "$err")" >&2
      exit 2
    fi
    while IFS= read -r line; do
      line=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
      [ "${#line}" -ge 12 ] || continue
      if grep -qF -- "$line" "$@" 2> /dev/null; then
        echo "feeding-back: text of the participant issue $u appears in what would be written; participant text never enters a finding, an issue, a comment or a log" >&2
        exit 64
      fi
    done < "$bodyf"
  done < <(participant_urls)
  rm -f "$bodyf"
  trap - EXIT
}

if [ "$sub" = apply ]; then
  refuse_participant_text "$ledger" "$scratch/intake.md" "$arch" "$people"
  if [ ! -s "$ledger" ]; then
    echo "feeding-back: no route.md; nothing to apply"
    exit 0
  fi
  # One record per block, separated by the unit separator, which `read` keeps empty fields
  # across where it would not across a tab: title decision inputs sources summary repo class
  # priority mvp type existing reason architecture. A missing field is empty.
  blocks=$(awk '
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); gsub(/\t/, " ", s); return s }
    function flush() {
      if (title == "") return
      printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n", title, f["decision"], f["inputs"], f["sources"], f["summary"], f["repo"], f["class"], f["priority"], f["mvp"], f["type"], f["existing"], f["reason"], f["architecture"]
      title = ""
    }
    /^## / { flush(); title = trim(substr($0, 4)); split("", f); next }
    title != "" && /^[ \t]*-[ \t]*[a-z]+:/ {
      line = $0; sub(/^[ \t]*-[ \t]*/, "", line)
      key = line; sub(/:.*$/, "", key)
      f[key] = trim(substr(line, length(key) + 2))
    }
    END { flush() }
  ' "$ledger")
  touch "$applied"

  n=0
  while IFS=$'\037' read -r title decision inputs sources summary repo class priority mvp type existing reason architecture; do
    [ -n "$title" ] || continue
    n=$((n + 1))
    key=$(printf '%s' "$title" | sha256sum | cut -c1-16)
    if grep -q "^$key	" "$applied"; then
      echo "feeding-back: already applied: $title"
      continue
    fi
    case "$inputs" in '' | *[!0-9]*) echo "feeding-back: block $n has no numeric inputs: $title" >&2; exit 64 ;; esac
    [ "$inputs" -ge 1 ] || { echo "feeding-back: block $n has no inputs: $title" >&2; exit 64; }
    result=
    case "$decision" in
      drop)
        [ -n "$reason" ] || { echo "feeding-back: a dropped group names no reason: $title" >&2; exit 64; }
        result=-
        ;;
      route | merge)
        [ -n "$sources" ] || { echo "feeding-back: $decision needs sources to cite: $title" >&2; exit 64; }
        [ -n "$summary" ] || { echo "feeding-back: $decision needs a summary: $title" >&2; exit 64; }
        case "$architecture" in '' | yes | no) ;; *) echo "feeding-back: architecture is neither yes nor no: $title" >&2; exit 64 ;; esac
        archtext=
        if [ "$architecture" = yes ]; then
          archtext=$(arch_section "$title") || exit 64
        fi
        cites=
        IFS=, read -ra urls <<< "$sources"
        for u in "${urls[@]}"; do
          u=$(printf '%s' "$u" | tr -d ' ')
          printf '%s\n' "$u" | grep -Eq '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/issues/[0-9]+(#issuecomment-[0-9]+)?$' \
            || { echo "feeding-back: a source is not an issue or comment URL ($u): $title" >&2; exit 64; }
          cites="$cites- $u"$'\n'
        done
        if [ "$decision" = route ]; then
          printf '%s\n' "$repo" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || { echo "feeding-back: repo is not owner/repo: $title" >&2; exit 64; }
          [ "$class" = bug ] || [ "$class" = enhancement ] || { echo "feeding-back: class is neither bug nor enhancement: $title" >&2; exit 64; }
          printf '%s\n' "$priority" | grep -Eq '^P[0-9]-[a-z]+$' || { echo "feeding-back: no proposed priority label: $title" >&2; exit 64; }
          [ "$mvp" = yes ] || [ "$mvp" = no ] || { echo "feeding-back: mvp is neither yes nor no: $title" >&2; exit 64; }
          case "$type" in Architecting | Materializing | Developing) ;; *) echo "feeding-back: type is none of Architecting, Materializing, Developing: $title" >&2; exit 64 ;; esac
          body=$scratch/route.body.md
          {
            printf '%s\n\n' "$summary"
            [ -z "$archtext" ] || printf '%s\n' "$archtext"
            printf 'Proposed for: %s. The labels are a proposal; triage decides.\n\n' "$type"
            printf 'Origin, from the weekly digest %s:\n%s' "$digest" "$cites"
          } > "$body"
          refuse_closing "$title"$'\n'"$(cat "$body")"
          labels=("$NEEDS_TRIAGE" "$class" "$priority")
          [ "$mvp" = yes ] && labels+=("$MVP")
          args=()
          for l in "${labels[@]}"; do args+=(--label "$l"); done
          if ! url=$(gh issue create --repo "$repo" --title "$title" --body-file "$body" "${args[@]}" 2> "$err"); then
            echo "REFUSED: $repo did not take the issue \"$title\": $(cat "$err")" >&2
            exit 2
          fi
          result=$(printf '%s\n' "$url" | grep -Eo 'https://github\.com/[^[:space:]]+' | tail -1 || true)
          result=${result:--}
        else
          printf '%s\n' "$existing" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+$' || { echo "feeding-back: existing is not owner/repo#N: $title" >&2; exit 64; }
          erepo=${existing%#*}
          enum=${existing#*#}
          if [ "$erepo" = "$digest_repo" ] && [ "$enum" = "$digest_number" ]; then
            echo "feeding-back: a finding is never merged into the digest itself: $title" >&2
            exit 64
          fi
          if ! state=$(gh issue view "$enum" --repo "$erepo" --json state --jq .state 2> "$err"); then
            echo "REFUSED: could not read $existing: $(cat "$err")" >&2
            exit 2
          fi
          if [ "$state" != OPEN ]; then
            echo "feeding-back: $existing is $state, not open: route the group instead of merging it: $title" >&2
            exit 64
          fi
          body=$scratch/route.body.md
          {
            printf 'A finding restates this issue (%s input(s)): %s\n\n%s\n\n' "$inputs" "$title" "$summary"
            [ -z "$archtext" ] || printf '%s\n' "$archtext"
            printf 'Origin, from the weekly digest %s:\n%s' "$digest" "$cites"
          } > "$body"
          refuse_closing "$(cat "$body")"
          if ! url=$(gh issue comment "$enum" --repo "$erepo" --body-file "$body" 2> "$err"); then
            echo "REFUSED: $existing did not take the comment: $(cat "$err")" >&2
            exit 2
          fi
          result=$(printf '%s\n' "$url" | grep -Eo 'https://github\.com/[^[:space:]]+' | tail -1 || true)
          result=${result:-$existing}
        fi
        ;;
      *)
        echo "feeding-back: decision is none of route, merge, drop: $title" >&2
        exit 64
        ;;
    esac
    printf '%s\t%s\t%s\t%s\n' "$key" "$decision" "$inputs" "$result" >> "$applied"
    echo "feeding-back: $decision ($inputs): $title${result:+ $result}"
  done <<< "$blocks"
  exit 0
fi

if [ "$sub" = reply ]; then
  if [ ! -s "$people" ]; then
    echo "feeding-back: no participants.md; no participant issue to answer"
    exit 0
  fi
  refuse_participant_text "$ledger" "$scratch/intake.md" "$arch" "$people"
  disclaimer='> *This was generated by AI during triage.*'
  # One record per block, as in apply: ref url kind action labels.
  pblocks=$(awk '
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); gsub(/\t/, " ", s); return s }
    function flush() {
      if (title == "") return
      printf "%s\037%s\037%s\037%s\037%s\n", title, f["url"], f["kind"], f["action"], f["labels"]
      title = ""
    }
    /^## / { flush(); title = trim(substr($0, 4)); split("", f); next }
    title != "" && /^[ \t]*-[ \t]*[a-z]+:/ {
      line = $0; sub(/^[ \t]*-[ \t]*/, "", line)
      key = line; sub(/:.*$/, "", key)
      f[key] = trim(substr(line, length(key) + 2))
    }
    END { flush() }
  ' "$people")
  touch "$people_applied"
  n=0
  while IFS=$'\037' read -r ref url kind action labels; do
    [ -n "$ref" ] || continue
    n=$((n + 1))
    printf '%s\n' "$url" | grep -Eq '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/issues/[0-9]+$' \
      || { echo "feeding-back: participant block $n has no issue URL: $ref" >&2; exit 64; }
    key=$(printf '%s' "$url" | sha256sum | cut -c1-16)
    if grep -q "^$key	" "$people_applied"; then
      echo "feeding-back: already answered: $url"
      continue
    fi
    prepo=$(issue_repo "$url")
    pnum=${url##*/}
    if [ "$prepo" = "$digest_repo" ] && [ "$pnum" = "$digest_number" ]; then
      echo "feeding-back: the digest is not a participant issue: $url" >&2
      exit 64
    fi
    case "$kind" in public | relayed) ;; *) echo "feeding-back: kind is neither public nor relayed: $url" >&2; exit 64 ;; esac
    case "$action" in acknowledge | label | escalate) ;; *) echo "feeding-back: action is none of acknowledge, label, escalate: $url" >&2; exit 64 ;; esac
    if [ "$kind" = relayed ] && [ "$action" = acknowledge ]; then
      echo "feeding-back: nothing is posted on a relayed issue, labels only: $url" >&2
      exit 64
    fi
    want=
    if [ -n "$labels" ]; then
      IFS=, read -ra ls <<< "$labels"
      for l in "${ls[@]}"; do
        l=$(printf '%s' "$l" | tr -d ' ')
        case "$l" in
          needs-info | ready-for-agent | ready-for-human | wontfix | needs-triage) want="$want $l" ;;
          *) echo "feeding-back: label $l is not one a participant issue may take: $url" >&2; exit 64 ;;
        esac
      done
    fi
    [ "$action" != escalate ] || want="$want ready-for-human"
    if [ "$kind" = public ] && [ "$action" = label ]; then
      echo "feeding-back: a public issue gets the acknowledgement or ready-for-human, not labels alone: $url" >&2
      exit 64
    fi
    if [ "$action" = label ] && [ -z "${want# }" ]; then
      echo "feeding-back: a label action names no label: $url" >&2
      exit 64
    fi
    if ! has=$(gh issue view "$pnum" --repo "$prepo" --json labels --jq '[.labels[].name] | join(",")' 2> "$err"); then
      echo "REFUSED: could not read $url: $(cat "$err")" >&2
      exit 2
    fi
    case ",$has," in *,relayed,*) is_relayed=yes ;; *) is_relayed=no ;; esac
    if [ "$kind" = relayed ] && [ "$is_relayed" != yes ]; then
      echo "feeding-back: $url is listed as relayed but carries no relayed label: $url" >&2
      exit 64
    fi
    if [ "$kind" = public ] && [ "$is_relayed" = yes ]; then
      echo "feeding-back: $url is listed as public but carries the relayed label; a relayed issue gets labels only" >&2
      exit 64
    fi
    for l in $(printf '%s\n' $want | sort -u); do
      if ! gh issue edit "$pnum" --repo "$prepo" --add-label "$l" > /dev/null 2> "$err"; then
        echo "REFUSED: $url did not take the label $l: $(cat "$err")" >&2
        exit 2
      fi
    done
    if [ "$action" = acknowledge ]; then
      marker="<!-- spoolway-feeding-back-reply: $run -->"
      # Only a marker written by the account gh posts as counts: anyone can copy the prefix.
      if ! me=$(gh api user --jq .login 2> "$err") || ! printf '%s' "$me" | grep -qE '^[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?$'; then
        echo "REFUSED: could not tell which account posts the acknowledgements: $(cat "$err")" >&2
        exit 2
      fi
      if ! seen=$(gh api "repos/$prepo/issues/$pnum/comments" --paginate --jq ".[] | select(.user.login == \"$me\" and (.body | contains(\"<!-- spoolway-feeding-back-reply:\"))) | .html_url" 2> "$err"); then
        echo "REFUSED: could not read the comments of $url: $(cat "$err")" >&2
        exit 2
      fi
      if [ -z "$(printf '%s\n' "$seen" | grep -E '^https://github\.com/' | head -1 || true)" ]; then
        pbody=$scratch/participant.reply.md
        {
          echo "$disclaimer"
          echo
          echo "Thanks for the feedback. It is recorded and a person will read it. This is an automated acknowledgement, not an answer."
          echo "$marker"
        } > "$pbody"
        if ! gh issue comment "$pnum" --repo "$prepo" --body-file "$pbody" > /dev/null 2> "$err"; then
          echo "REFUSED: $url did not take the acknowledgement: $(cat "$err")" >&2
          exit 2
        fi
      fi
    fi
    printf '%s\t%s\t%s\n' "$key" "$action" "$url" >> "$people_applied"
    echo "feeding-back: $action ($kind): $url"
  done <<< "$pblocks"
  exit 0
fi

if [ "$sub" = rotate ]; then
  # The next digest is titled by the ISO week after today's, and starts with "weekly digest" so
  # `findings.sh` finds it. Open first, close second: a failure between them leaves two digests
  # open (`findings.sh` takes the newest), never none.
  today=${FEEDING_BACK_TODAY:-$(date -u +%F)}
  title="Weekly digest $(date -u -d "$today +7 days" +%G-W%V)"
  if ! open=$(gh issue list --repo "$digest_repo" --state open --limit 100 --search "weekly digest in:title sort:created-desc" --json number,title \
    --jq '.[] | select(.title | ascii_downcase | startswith("weekly digest")) | .number' 2> "$err"); then
    echo "REFUSED: could not read $digest_repo to find the open digests: $(cat "$err")" >&2
    exit 2
  fi
  others=$(printf '%s\n' "$open" | grep -E '^[0-9]+$' | grep -vxF "$digest_number" | head -1 || true)
  if [ -n "$others" ]; then
    echo "feeding-back: $digest_repo#$others is already open as the next digest; none opened"
  else
    body=$scratch/rotate.body.md
    {
      echo "The weekly digest of the project. A run's findings are comments here; the weekly Feeding-back batch bound to this issue routes them into triage issues and counts what it did, then opens the next digest and closes this one."
      echo
      echo "Opened by the \`rotate\` step of the batch \`$run\`, which processed the digest \`$digest\`."
    } > "$body"
    refuse_closing "$title"$'\n'"$(cat "$body")"
    if ! url=$(gh issue create --repo "$digest_repo" --title "$title" --body-file "$body" 2> "$err"); then
      echo "REFUSED: $digest_repo did not take the next digest: $(cat "$err")" >&2
      exit 2
    fi
    url=$(printf '%s\n' "$url" | grep -Eo 'https://github\.com/[^[:space:]]+' | tail -1 || true)
    echo "feeding-back: opened the next digest \"$title\" ${url:-}"
  fi
  if ! state=$(gh issue view "$digest_number" --repo "$digest_repo" --json state --jq .state 2> "$err"); then
    echo "REFUSED: could not read the digest $digest: $(cat "$err")" >&2
    exit 2
  fi
  if [ "$state" = OPEN ]; then
    if ! gh issue close "$digest_number" --repo "$digest_repo" --reason completed > /dev/null 2> "$err"; then
      echo "REFUSED: $digest was not closed: $(cat "$err")" >&2
      exit 2
    fi
    echo "feeding-back: closed the processed digest $digest"
  else
    echo "feeding-back: the processed digest $digest is already $state"
  fi
  exit 0
fi

# counts
posted=$scratch/feeding-back.$run.url
marker="<!-- spoolway-feeding-back: $run -->"
if [ -s "$posted" ]; then
  echo "feeding-back: counts already posted for run $run: $(cat "$posted")"
  exit 0
fi

routed=0 merged=0 dropped=0
if [ -s "$applied" ]; then
  routed=$(awk -F'\t' '$2 == "route" { n += $3 } END { print n + 0 }' "$applied")
  merged=$(awk -F'\t' '$2 == "merge" { n += $3 } END { print n + 0 }' "$applied")
  dropped=$(awk -F'\t' '$2 == "drop" { n += $3 } END { print n + 0 }' "$applied")
fi
received=$((routed + merged + dropped))
# The intake's own total, when it wrote one, must be the sum of what route decided.
if [ -s "$scratch/intake.md" ]; then
  stated=$(sed -n -E 's/^received:[ \t]*([0-9]+)[ \t]*$/\1/p' "$scratch/intake.md" | head -1)
  if [ -n "$stated" ] && [ "$stated" -ne "$received" ]; then
    echo "feeding-back: intake received $stated inputs and route decided $received: every input is routed, merged or dropped" >&2
    exit 65
  fi
fi

answered=
if [ -s "$people_applied" ]; then
  answered="$(awk -F'\t' '$2 == "acknowledge" { a++ } $2 == "label" { l++ } $2 == "escalate" { e++ } END { printf "%d acknowledged, %d labelled, %d left for a person", a, l, e }' "$people_applied")"
fi
body=$scratch/feeding-back.body.md
{
  echo "## Weekly batch \`$run\`"
  echo
  echo "- Received: $received"
  echo "- Routed: $routed"
  echo "- Merged into an existing issue: $merged"
  echo "- Dropped: $dropped"
  [ -z "$answered" ] || echo "- Participant issues answered: $answered"
  echo
  if [ -s "$applied" ]; then
    awk -F'\t' '$2 == "route" && $4 != "-" { print "- Routed: " $4 }' "$applied"
  fi
  if [ -s "$scratch/merged-since-last.md" ]; then
    echo
    echo "Routed by the last batch and merged since:"
    cat "$scratch/merged-since-last.md"
  fi
  echo "$marker"
} > "$body"

if ! existing=$(gh api "repos/$digest_repo/issues/$digest_number/comments" --paginate \
  --jq ".[] | select(.body | contains(\"$marker\")) | .html_url" 2> "$err"); then
  echo "REFUSED: could not read the comments of $digest: $(cat "$err")" >&2
  exit 2
fi
refuse_participant_text "$body" "$scratch/merged-since-last.md"
existing=$(printf '%s\n' "$existing" | grep -E '^https://github\.com/' | head -1 || true)
if [ -n "$existing" ]; then
  echo "$existing" > "$posted"
  echo "feeding-back: counts already posted for run $run: $existing"
  exit 0
fi
if ! url=$(gh issue comment "$digest" --body-file "$body" 2> "$err"); then
  echo "REFUSED: $digest did not take the counts: $(cat "$err")" >&2
  exit 2
fi
url=$(printf '%s\n' "$url" | grep -Eo 'https://github\.com/[^[:space:]]+' | tail -1 || true)
echo "${url:-$digest}" > "$posted"
echo "feeding-back: counted $received received, $routed routed, $merged merged, $dropped dropped on ${url:-$digest}"
